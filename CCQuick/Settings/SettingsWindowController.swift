import AppKit
import SwiftUI

class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

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