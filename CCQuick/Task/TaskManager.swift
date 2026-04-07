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

        // 写入 prompt 文件
        let promptFile = workDirURL.appendingPathComponent("prompt.txt")
        try? trimmed.write(to: promptFile, atomically: true, encoding: .utf8)

        // 检查执行账户类型
        let settings = AppSettings.current
        if settings.executionAccount == .codingPlan {
            let apiKey = settings.codingPlanApiKey.trimmingCharacters(in: .whitespaces)
            if !apiKey.isEmpty {
                let providers = CodingPlanProvider.matchProviders(for: apiKey)
                if let provider = providers.first {
                    // 两阶段执行
                    twoStageExecute(
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
        executeDirectly(prompt: trimmed, workDir: workDir)
    }

    /// 两阶段执行
    private func twoStageExecute(
        prompt: String,
        workDir: String,
        provider: CodingPlanProvider,
        apiKey: String
    ) {
        logInfo("第一阶段：询问 LLM...", category: "Task")

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
                    await handleQuickAnswer(prompt: prompt, workDir: workDir, answer: answer)
                } else if let plan = response.plan {
                    // 需要计划执行
                    logInfo("需要计划执行: \(plan.prefix(50))...", category: "Task")
                    await executeWithPlan(prompt: prompt, workDir: workDir, plan: plan)
                } else {
                    // 异常情况，直接执行
                    logWarning("第一阶段返回无效响应，直接执行", category: "Task")
                    executeDirectly(prompt: prompt, workDir: workDir)
                }
            } catch {
                logError("第一阶段失败: \(error.localizedDescription)", category: "Task")
                // 降级：直接执行
                executeDirectly(prompt: prompt, workDir: workDir)
            }
        }
    }

    /// 处理快速回答
    private func handleQuickAnswer(prompt: String, workDir: String, answer: String) async {
        let id = URL(fileURLWithPath: workDir).lastPathComponent

        // 写入响应文件
        let workDirURL = URL(fileURLWithPath: workDir)
        let responseFile = workDirURL.appendingPathComponent("response.txt")
        try? answer.write(to: responseFile, atomically: true, encoding: .utf8)

        // 创建已完成的任务
        var task = CCTask(
            id: id,
            prompt: prompt,
            workDir: workDir,
            status: .completed,
            startedAt: .now,
            finishedAt: .now,
            response: answer,
            viewed: false
        )

        // 保存任务
        do {
            try TaskStore.shared.save(task)
        } catch {
            logError("保存任务失败: \(error)", category: "Task")
        }

        // 添加到未查看列表
        unviewedTasks.append(task)

        // 通知
        onTaskCompleted?(task)
        NotificationService.shared.notify(task: task)
    }

    /// 带计划执行
    private func executeWithPlan(prompt: String, workDir: String, plan: String) async {
        let id = URL(fileURLWithPath: workDir).lastPathComponent

        let task = CCTask(
            id: id,
            prompt: prompt,
            workDir: workDir,
            status: .running,
            startedAt: .now,
            finishedAt: nil,
            response: "",
            viewed: false
        )

        runningTasks.append(task)
        logDebug("任务添加到 runningTasks, count=\(runningTasks.count)", category: "Task")

        do {
            try TaskStore.shared.save(task)
        } catch {
            logError("保存任务失败: \(error)", category: "Task")
        }

        logInfo("启动 TaskRunner.runWithPlan...", category: "Task")
        TaskRunner.runWithPlan(task: task, plan: plan, onOutput: { output in
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
    private func executeDirectly(prompt: String, workDir: String) {
        let id = URL(fileURLWithPath: workDir).lastPathComponent

        let task = CCTask(
            id: id,
            prompt: prompt,
            workDir: workDir,
            status: .running,
            startedAt: .now,
            finishedAt: nil,
            response: "",
            viewed: false
        )

        runningTasks.append(task)
        logDebug("任务添加到 runningTasks, count=\(runningTasks.count)", category: "Task")

        do {
            try TaskStore.shared.save(task)
            logDebug("任务已保存: \(id)", category: "Task")
        } catch {
            logError("保存任务失败: \(error)", category: "Task")
        }

        logInfo("启动 TaskRunner...", category: "Task")
        TaskRunner.run(task: task, onOutput: { output in
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

    var unviewedCount: Int { unviewedTasks.count }
    var hasRunning: Bool { !runningTasks.isEmpty }
}
