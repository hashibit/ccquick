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
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 520),
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

        // 添加 ESC 键监听
        setupEscapeMonitor()
    }

    func hide() {
        window?.orderOut(nil)
        removeEscapeMonitor()
    }

    private func setupEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, // ESC
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
        // 窗口失去焦点时移除 ESC 监听
        removeEscapeMonitor()
    }
}