import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var _window: NSWindow?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.delegate = self
        _window = window
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        // 只关闭 SwiftUI 的 Settings 窗口（标题为空的窗口）
        for window in NSApp.windows {
            if window != self.window && window.title.isEmpty && window.styleMask.contains(.titled) {
                window.close()
            }
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window?.orderOut(nil)
        return false
    }
}