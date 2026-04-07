import AppKit
import SwiftUI

class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var escapeMonitor: Any?

    private override init() {
        super.init()
    }

    func show() {
        if window == nil {
            let view = SettingsView()
            let hostingView = NSHostingView(rootView: view)

            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 480),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "设置"
            newWindow.center()
            newWindow.minSize = NSSize(width: 500, height: 400)
            newWindow.contentView = hostingView
            newWindow.delegate = self
            window = newWindow
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupEscapeMonitor()

        // 显示 Dock 图标
        NSApp.setActivationPolicy(.regular)
    }

    func hide() {
        window?.orderOut(nil)
        removeEscapeMonitor()

        // 如果没有其他窗口，隐藏 Dock 图标
        checkHideDockIcon()
    }

    private func setupEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53,
               let window = event.window,
               window === self?.window {
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    private func checkHideDockIcon() {
        // 检查是否还有可见窗口（排除菜单栏面板）
        let hasVisibleWindows = NSApp.windows.contains { window in
            window.isVisible &&
            window.styleMask.contains(.titled) &&
            window !== self.window
        }
        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    deinit {
        removeEscapeMonitor()
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        removeEscapeMonitor()
    }
}