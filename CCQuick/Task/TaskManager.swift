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
                    // 两阶段执行
                    twoStageExecute(
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

        // 默认 Claude 订阅：直接执行（无两阶段）
        executeDirectly(task: task, prompt: trimmed)
    }

    /// 两阶段执行
    private func twoStageExecute(
        task: CCTask,
        prompt: String,
        workDir: String,
        provider: CodingPlanProvider,
        apiKey: String
    ) {
        logInfo("第一阶段：询问 LLM...", category: "Task")

        // 保存任务状态
        do {
            try TaskStore.shared.save(task)
        } catch {
            logError("保存任务失败: \(error)", category: "Task")
        }

        Task {
            do {
                let response = try await APIClient.ask(
                    prompt: prompt,
                    provider: provider,
                    apiKey: apiKey
                )

                if response.canAnswerDirectly, let answer = response.answer {
                    // 直接回答
                    logInfo("直接回答任务", category: "Task")
                    await handleQuickAnswer(task: task, answer: answer)
                } else if let plan = response.plan {
                    // 需要计划执行
                    logInfo("需要计划执行: \(plan.prefix(50))...", category: "Task")
                    await executeWithPlan(task: task, plan: plan, userPrompt: prompt)
                } else {
                    // 异常情况，直接执行
                    logWarning("第一阶段返回无效响应，直接执行", category: "Task")
                    executeDirectly(task: task, prompt: prompt)
                }
            } catch {
                logError("第一阶段失败: \(error.localizedDescription)", category: "Task")
                // 降级：直接执行
                executeDirectly(task: task, prompt: prompt)
            }
        }
    }

    /// 处理快速回答
    private func handleQuickAnswer(task: CCTask, answer: String) async {
        // 写入 assistant 消息到 session.jsonl
        try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
            type: .assistant,
            content: answer
        ))

        // 更新任务状态
        var completedTask = task
        completedTask.status = .completed
        completedTask.finishedAt = .now
        completedTask.viewed = false

        // 从 runningTasks 移除，添加到未查看列表
        runningTasks.removeAll { $0.id == task.id }
        unviewedTasks.append(completedTask)

        // 保存任务
        do {
            try TaskStore.shared.save(completedTask)
        } catch {
            logError("保存任务失败: \(error)", category: "Task")
        }

        // 通知
        onTaskCompleted?(completedTask)
        NotificationService.shared.notify(task: completedTask, response: answer)
    }

    /// 带计划执行
    private func executeWithPlan(task: CCTask, plan: String, userPrompt: String) async {
        // 保存任务
        do {
            try TaskStore.shared.save(task)
        } catch {
            logError("保存任务失败: \(error)", category: "Task")
        }

        logInfo("启动 TaskRunner.runWithPlan...", category: "Task")
        TaskRunner.runWithPlan(task: task, plan: plan, userPrompt: userPrompt, onOutput: { output in
            logDebug("任务输出: \(output.prefix(100))", category: "Task")
        }, onComplete: { [weak self] completed in
            guard let self = self else { return }
            logInfo("任务完成: \(completed.id), status=\(completed.status.rawValue)", category: "Task")
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

    /// 直接执行（无两阶段）
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
            logInfo("任务完成: \(completed.id), status=\(completed.status.rawValue)", category: "Task")
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
                logInfo("追问完成: \(completed.id)", category: "Task")
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

    var unviewedCount: Int { unviewedTasks.count }
    var hasRunning: Bool { !runningTasks.isEmpty }
}