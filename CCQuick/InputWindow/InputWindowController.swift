import AppKit
import SwiftUI
import ApplicationServices
import Carbon

class InputWindowController: NSObject {
    static let shared = InputWindowController()

    private var panel: KeyPanel?
    private var escapeMonitor: Any?
    private var hotkeyRef: EventHotKeyRef?
    private var hotkeyHandler: EventHandlerRef?

    var onSubmit: ((String) -> Void)?

    override init() {
        super.init()
        setupPanel()
        registerHotkey()
    }

    private func setupPanel() {
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 56),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let inputView = InputView { [weak self] prompt in
            logInfo("InputView onSubmit 被调用: \(prompt.prefix(50))", category: "Input")
            self?.hide()
            self?.onSubmit?(prompt)
            logDebug("onSubmit 回调已执行", category: "Input")
        } onCancel: { [weak self] in
            logInfo("InputView onCancel 被调用", category: "Input")
            self?.hide()
        }

        let hostingView = NSHostingView(rootView: inputView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 56)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        self.panel = panel
        centerPanel()

        // 监听面板内的 ESC 键
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, // ESC
               let window = event.window,
               window === self?.panel {
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func centerPanel() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.maxY - 200
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - 全局快捷键（使用 Carbon API）

    private func registerHotkey() {
        let settings = AppSettings.current

        // 安装事件处理器
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, _, _) -> OSStatus in
                InputWindowController.shared.handleHotkey()
                return noErr
            },
            1,
            &eventType,
            nil,
            &hotkeyHandler
        )

        // 注册热键
        let status = RegisterEventHotKey(
            settings.hotkeyKeyCode,
            settings.hotkeyModifiers,
            EventHotKeyID(signature: OSType(0x43435175), id: 1), // 'CCQu'
            GetEventDispatcherTarget(),
            0,
            &hotkeyRef
        )

        print("[Hotkey] 注册状态: \(status == noErr ? "✓ 成功" : "✗ 失败 (code=\(status))")")
        print("[Hotkey] 当前快捷键: \(AppSettings.hotkeyDisplayString)")
    }

    // 更新快捷键（设置变更时调用）
    func updateHotkey() {
        // 先注销旧的
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }

        // 重新注册新的
        let settings = AppSettings.current
        let status = RegisterEventHotKey(
            settings.hotkeyKeyCode,
            settings.hotkeyModifiers,
            EventHotKeyID(signature: OSType(0x43435175), id: 1),
            GetEventDispatcherTarget(),
            0,
            &hotkeyRef
        )

        print("[Hotkey] 更新快捷键: \(status == noErr ? "✓ 成功" : "✗ 失败")")
        print("[Hotkey] 新快捷键: \(AppSettings.hotkeyDisplayString)")
    }

    private func handleHotkey() {
        print("[Hotkey] 快捷键触发!")
        Task { @MainActor in
            self.toggle()
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
        // 让 textField 成为 first responder，并将光标移到末尾
        DispatchQueue.main.async {
            if let contentView = self.panel?.contentView,
               let textField = self.findTextField(in: contentView) {
                self.panel?.makeFirstResponder(textField)
                // 将光标移到末尾
                if let editor = textField.currentEditor() {
                    let len = textField.stringValue.count
                    editor.selectedRange = NSRange(location: len, length: 0)
                }
            }
        }
    }

    private func findTextField(in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField {
            return textField
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview) {
                return found
            }
        }
        return nil
    }

    func hide() {
        panel?.orderOut(nil)
    }

    deinit {
        if let ref = hotkeyRef { UnregisterEventHotKey(ref) }
        if let handler = hotkeyHandler { RemoveEventHandler(handler) }
        if let m = escapeMonitor { NSEvent.removeMonitor(m) }
    }
}

// 自定义 NSPanel 子类，确保 borderless 面板能成为 key window
class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}