import AppKit
import SwiftUI
import ApplicationServices

class InputWindowController: NSObject {
    static let shared = InputWindowController()

    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var onSubmit: ((String) -> Void)?

    override init() {
        super.init()
        setupPanel()
        registerHotkey()
    }

    private func setupPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 64),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let inputView = InputView { [weak self] prompt in
            self?.hide()
            self?.onSubmit?(prompt)
        } onCancel: { [weak self] in
            self?.hide()
        }

        let hostingView = NSHostingView(rootView: inputView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 620, height: 64)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        self.panel = panel
        centerPanel()
    }

    private func centerPanel() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.maxY - 200
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - 全局快捷键 ⌘⇧Space

    private func registerHotkey() {
        // 检查辅助功能权限
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            promptAccessibilityPermission()
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isHotkey(event) == true {
                DispatchQueue.main.async { self?.toggle() }
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isHotkey(event) == true {
                DispatchQueue.main.async { self?.toggle() }
                return nil
            }
            return event
        }
    }

    private func isHotkey(_ event: NSEvent) -> Bool {
        // ⌘⇧Space (keyCode 49)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == [.command, .shift] && event.keyCode == 49
    }

    private func promptAccessibilityPermission() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "CCQuick 需要辅助功能权限来监听全局快捷键 ⌘⇧Space。\n请前往「系统设置 → 隐私与安全性 → 辅助功能」开启。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后再说")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    // MARK: - Show / Hide

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        centerPanel()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
}
