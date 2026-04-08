import AppKit
import SwiftUI
import UserNotifications
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var inputWindowController: InputWindowController?
    private var settingsHotkeyMonitor: Any?
    private var historyHotkeyRef: EventHotKeyRef?
    private var historyHotkeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 应用保存的主题设置
        SettingsStore.shared.applyAppearance()

        // 请求通知权限
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // 注册通知响应：点击通知 → 独立任务详情窗口
        NotificationService.shared.onTaskNotificationClicked = { taskId in
            let controller = TaskDetailWindowController(taskId: taskId)
            controller.show()
        }

        // 初始化菜单栏图标
        statusItemController = StatusItemController()

        // 初始化输入窗口（含全局快捷键）
        inputWindowController = InputWindowController.shared
        InputWindowController.shared.onSubmit = { [weak self] prompt in
            logInfo("收到提交请求: \(prompt.prefix(50))...", category: "App")
            self?.statusItemController?.taskManager.submit(prompt: prompt)
            logDebug("任务已提交到 TaskManager", category: "App")
        }

        // 监听 TaskManager 变化，更新菜单栏图标
        statusItemController?.startObserving()

        // 注册 cmd+, 快捷键
        registerSettingsHotkey()

        // 注册 cmd+shift+h 全局快捷键
        registerHistoryHotkey()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func registerSettingsHotkey() {
        // 监听本地键盘事件，拦截 cmd+,
        settingsHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isSettingsHotkey(event) == true {
                Task { @MainActor in
                    SettingsWindowController.shared.show()
                }
                return nil  // 拦截事件
            }
            return event
        }
    }

    private func isSettingsHotkey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // cmd+, (keyCode 43)
        return flags == .command && event.keyCode == 43
    }

    private func registerHistoryHotkey() {
        // 安装事件处理器
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event!, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                if hotKeyID.id == 2 {
                    Task { @MainActor in
                        HistoryWindowController.shared.show()
                    }
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            nil,
            &historyHotkeyHandler
        )

        // 注册热键: cmd+shift+h
        // keyCode 4 = 'h', modifiers: cmd + shift
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let status = RegisterEventHotKey(
            4, // keyCode for 'h'
            modifiers,
            EventHotKeyID(signature: OSType(0x48535459), id: 2), // 'HSTR' for history
            GetEventDispatcherTarget(),
            0,
            &historyHotkeyRef
        )

        print("[HistoryHotkey] 注册状态: \(status == noErr ? "✓ 成功" : "✗ 失败 (code=\(status))")")
    }

    deinit {
        if let m = settingsHotkeyMonitor {
            NSEvent.removeMonitor(m)
        }
        if let ref = historyHotkeyRef { UnregisterEventHotKey(ref) }
        if let handler = historyHotkeyHandler { RemoveEventHandler(handler) }
    }
}
