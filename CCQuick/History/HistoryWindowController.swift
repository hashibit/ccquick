import AppKit
import SwiftUI

class HistoryWindowController: NSWindowController {
    static let shared = HistoryWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()
        window.contentView = NSHostingView(rootView: HistoryView())
        window.minSize = NSSize(width: 800, height: 500)
        // 自动保存窗口位置和大小
        window.setFrameAutosaveName("HistoryWindow")
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(selectingTaskId taskId: String? = nil) {
        // 应用当前主题
        Task { @MainActor in
            SettingsStore.shared.applyAppearance()
        }

        if !window!.isVisible {
            window?.center()
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 显示 Dock 图标
        NSApp.setActivationPolicy(.regular)

        if let taskId = taskId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(
                    name: .selectHistoryTask,
                    object: nil,
                    userInfo: ["taskId": taskId]
                )
            }
        }
    }
}

// MARK: - 单任务详情窗口

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
        checkHideDockIcon()
    }

    private func checkHideDockIcon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasVisibleWindows = NSApp.windows.contains { window in
                window.isVisible &&
                window.styleMask.contains(.titled) &&
                window !== self.window &&
                window !== HistoryWindowController.shared.window
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
            if let t = task {
                TaskDetailView(taskId: taskId)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .onAppear { loadTask() }
    }

    private func loadTask() {
        task = TaskStore.shared.load(id: taskId)
    }
}

extension HistoryWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        checkHideDockIcon()
    }

    private func checkHideDockIcon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasVisibleWindows = NSApp.windows.contains { window in
                window.isVisible &&
                window.styleMask.contains(.titled) &&
                window !== self.window
            }
            if !hasVisibleWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
