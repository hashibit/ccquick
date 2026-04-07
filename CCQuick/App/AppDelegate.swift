import AppKit
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var inputWindowController: InputWindowController?
    private var settingsHotkeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 请求通知权限
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // 注册通知响应：点击通知 → 历史窗口选中该任务
        NotificationService.shared.onTaskNotificationClicked = { taskId in
            HistoryWindowController.shared.show(selectingTaskId: taskId)
        }

        // 初始化菜单栏图标
        statusItemController = StatusItemController()

        // 初始化输入窗口（含全局快捷键）
        inputWindowController = InputWindowController()
        inputWindowController?.onSubmit = { [weak self] prompt in
            logInfo("收到提交请求: \(prompt.prefix(50))...", category: "App")
            self?.statusItemController?.taskManager.submit(prompt: prompt)
            logDebug("任务已提交到 TaskManager", category: "App")
        }

        // 监听 TaskManager 变化，更新菜单栏图标
        statusItemController?.startObserving()

        // 注册 cmd+, 快捷键
        registerSettingsHotkey()
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

    deinit {
        if let m = settingsHotkeyMonitor {
            NSEvent.removeMonitor(m)
        }
    }
}
