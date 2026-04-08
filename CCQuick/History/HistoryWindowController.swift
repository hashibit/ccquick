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
