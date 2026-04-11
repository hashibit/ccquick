import Foundation

@MainActor
@Observable
class TaskManager {
    static let shared = TaskManager()

    private(set) var runningTasks: [CCTask] = []
    private(set) var unviewedTasks: [CCTask] = []

    var onTaskCompleted: ((CCTask) -> Void)?

    private init() {
        reload()
    }

    // 从磁盘重新加载未查看任务
    func reload() {
        let all = TaskStore.shared.loadAll()
        unviewedTasks = all.filter { $0.status == .completed && !$0.viewed }
    }

    func submit(prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logWarning("提交的 prompt 为空", category: "Task")
            return
        }

        logInfo("提交任务: \(trimmed.prefix(50))...", category: "Task")

        let id = TaskStore.shared.makeTaskId(prompt: trimmed)
        let workDir = TaskStore.shared.baseDir.appendingPathComponent(id).path

        // 创建工作目录
        let workDirURL = URL(fileURLWithPath: workDir)
        try? FileManager.default.createDirectory(at: workDirURL, withIntermediateDirectories: true)

        // 写入 user 消息到 session.jsonl
        try? TaskStore.shared.appendMessage(id: id, message: SessionMessage(
            type: .user,
            content: trimmed
        ))

        // 创建任务
        let task = CCTask(
            id: id,
            workDir: workDir,
            status: .running,
            startedAt: .now,
            finishedAt: nil,
            viewed: false
        )

        runningTasks.append(task)
        logDebug("任务添加到 runningTasks, count=\(runningTasks.count)", category: "Task")

        // 检查执行账户类型
        let settings = AppSettings.current
        if settings.executionAccount == .codingPlan {
            let apiKey = settings.codingPlanApiKey.trimmingCharacters(in: .whitespaces)
            if !apiKey.isEmpty {
                let providers = CodingPlanProvider.matchProviders(for: apiKey)
                if let provider = providers.first {
                    executeWithHTTPTools(
                        task: task,
                        prompt: trimmed,
                        workDir: workDir,
                        provider: provider,
                        apiKey: apiKey
                    )
                    return
                }
            }
        }

        // 默认 Claude 订阅：直接执行
        executeDirectly(task: task, prompt: trimmed)
    }

    /// HTTP Tool Call 执行
    private func executeWithHTTPTools(
        task: CCTask,
        prompt: String,
        workDir: String,
        provider: CodingPlanProvider,
        apiKey: String
    ) {
        logInfo("HTTP Tool Call 执行...", category: "Task")

        do {
            try TaskStore.shared.save(task)
        } catch {
            logError("保存任务失败: \(error)", category: "Task")
        }

        Task {
            do {
                let response = try await APIClient.executeWithTools(
                    prompt: prompt,
                    provider: provider,
                    apiKey: apiKey,
                    workDir: workDir
                )

                // 写入 assistant 消息
                try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                    type: .assistant,
                    content: response
                ))

                var completedTask = task
                completedTask.status = .completed
                completedTask.finishedAt = .now
                completedTask.viewed = false

                logTaskCompleted(completedTask)
                runningTasks.removeAll { $0.id == task.id }
                unviewedTasks.append(completedTask)

                do {
                    try TaskStore.shared.save(completedTask)
                } catch {
                    logError("保存任务失败: \(error)", category: "Task")
                }

                onTaskCompleted?(completedTask)
                NotificationService.shared.notify(task: completedTask, response: response)
            } catch {
                logError("HTTP Tool Call 失败: \(error.localizedDescription)", category: "Task")

                try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                    type: .assistant,
                    content: "执行失败：\(error.localizedDescription)"
                ))

                var failed = task
                failed.status = .failed
                failed.finishedAt = .now

                logTaskCompleted(failed)
                runningTasks.removeAll { $0.id == task.id }

                do {
                    try TaskStore.shared.save(failed)
                } catch {
                    logError("保存任务失败: \(error)", category: "Task")
                }

                onTaskCompleted?(failed)
            }
        }
    }

    /// 直接执行
    private func executeDirectly(task: CCTask, prompt: String) {
        // 保存任务
        do {
            try TaskStore.shared.save(task)
            logDebug("任务已保存: \(task.id)", category: "Task")
        } catch {
            logError("保存任务失败: \(error)", category: "Task")
        }

        logInfo("启动 TaskRunner...", category: "Task")
        TaskRunner.run(task: task, prompt: prompt, onOutput: { output in
            logDebug("任务输出: \(output.prefix(100))", category: "Task")
        }, onComplete: { [weak self] completed in
            guard let self = self else { return }
            logTaskCompleted(completed)
            self.runningTasks.removeAll { $0.id == completed.id }
            if completed.status == .completed {
                self.unviewedTasks.append(completed)
            }
            do {
                try TaskStore.shared.save(completed)
            } catch {
                logError("保存完成任务失败: \(error)", category: "Task")
            }
            self.onTaskCompleted?(completed)
        })
    }

    func markViewed(taskId: String) {
        guard var task = unviewedTasks.first(where: { $0.id == taskId }) else { return }
        task.viewed = true
        do {
            try TaskStore.shared.save(task)
        } catch {
            print("Failed to mark task as viewed: \(error)")
        }
        unviewedTasks.removeAll { $0.id == taskId }
    }

    /// 追问：在当前任务的会话中继续对话，不创建新历史
    func followUp(task: CCTask, followUpPrompt: String) {
        guard task.status != .running else {
            logWarning("任务正在运行，无法追问", category: "Task")
            return
        }

        logInfo("追问任务: \(task.id), 内容: \(followUpPrompt.prefix(50))...", category: "Task")

        // 写入 user 消息到 session.jsonl
        try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
            type: .user,
            content: followUpPrompt
        ))

        // 将任务重新加入 runningTasks
        var runningTask = task
        runningTask.status = .running
        runningTask.finishedAt = nil
        runningTasks.append(runningTask)

        // 保存任务状态
        do {
            try TaskStore.shared.save(runningTask)
        } catch {
            logError("保存任务失败: \(error)", category: "Task")
        }

        // 执行追问（--continue 自动恢复会话上下文）
        TaskRunner.runFollowUp(
            task: runningTask,
            followUpPrompt: followUpPrompt,
            onOutput: { output in
                logDebug("追问输出: \(output.prefix(100))", category: "Task")
            },
            onComplete: { [weak self] completed in
                guard let self = self else { return }
                logTaskCompleted(completed)
                self.runningTasks.removeAll { $0.id == completed.id }
                do {
                    try TaskStore.shared.save(completed)
                } catch {
                    logError("保存完成任务失败: \(error)", category: "Task")
                }
                self.onTaskCompleted?(completed)
            }
        )
    }

    private func logTaskCompleted(_ task: CCTask) {
        let status = task.status == .completed ? "✅ 完成" : "❌ 失败"
        logInfo("\(status): \(task.id), 耗时: \(task.elapsedString)", category: "Task")
    }

    var unviewedCount: Int { unviewedTasks.count }
    var hasRunning: Bool { !runningTasks.isEmpty }
}