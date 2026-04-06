import AppKit
import SwiftUI

class HistoryWindowController: NSWindowController {
    static let shared = HistoryWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()
        window.contentView = NSHostingView(rootView: HistoryView())
        window.minSize = NSSize(width: 800, height: 500)
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(selectingTaskId taskId: String? = nil) {
        if !window!.isVisible {
            window?.center()
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

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
