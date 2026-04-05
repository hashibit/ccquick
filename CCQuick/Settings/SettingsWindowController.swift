import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CCQuick 设置"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.minSize = NSSize(width: 520, height: 300)
        window.maxSize = NSSize(width: 520, height: 300)
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        close()
    }
}