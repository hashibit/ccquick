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
        guard !trimmed.isEmpty else { return }

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
        do {
            try TaskStore.shared.save(task)
        } catch {
            print("Failed to save task: \(error)")
        }

        TaskRunner.run(task: task, onOutput: { _ in
            // 可用于实时更新输出（暂未使用）
        }, onComplete: { [weak self] completed in
            guard let self = self else { return }
            self.runningTasks.removeAll { $0.id == completed.id }
            if completed.status == .completed {
                self.unviewedTasks.append(completed)
            }
            do {
                try TaskStore.shared.save(completed)
            } catch {
                print("Failed to save completed task: \(error)")
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
