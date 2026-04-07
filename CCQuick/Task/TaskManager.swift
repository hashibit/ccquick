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

        let task = CCTask(
            id: id,
            prompt: trimmed,
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
