import AppKit
import SwiftUI

/// 历史窗口协调器：不再直接创建 AppKit 窗口，通过通知让 SwiftUI Window scene 管理窗口生命周期
class HistoryWindowController {
    static let shared = HistoryWindowController()
    private init() {}

    func show(selectingTaskId taskId: String? = nil) {
        Task { @MainActor in
            SettingsStore.shared.applyAppearance()
        }

        // 通知 HistoryWindowLauncher 打开 SwiftUI Window scene
        NotificationCenter.default.post(name: .openHistoryWindow, object: nil)

        if let taskId = taskId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: .selectHistoryTask,
                    object: nil,
                    userInfo: ["taskId": taskId]
                )
            }
        }
    }
}

// MARK: - 单任务详情窗口（独立 AppKit 窗口，不含 NavigationSplitView，无需迁移）

class TaskDetailWindowController: NSWindowController {
    private let taskId: String

    init(taskId: String) {
        self.taskId = taskId

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "任务详情"
        window.center()
        window.minSize = NSSize(width: 500, height: 400)
        window.contentView = NSHostingView(rootView: TaskDetailWindowView(taskId: taskId))
        window.setFrameAutosaveName("TaskDetailWindow-\(taskId)")
        window.hidesOnDeactivate = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        Task { @MainActor in
            SettingsStore.shared.applyAppearance()
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(.regular)
    }
}

extension TaskDetailWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasVisibleWindows = NSApp.windows.contains { window in
                window.isVisible && window.styleMask.contains(.titled) && window !== self.window
            }
            if !hasVisibleWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

/// 单任务详情窗口视图（简化版，无侧边栏）
struct TaskDetailWindowView: View {
    let taskId: String
    @State private var task: CCTask?

    var body: some View {
        VStack(spacing: 0) {
            if task != nil {
                TaskDetailView(taskId: taskId)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .onAppear { task = TaskStore.shared.load(id: taskId) }
    }
}
