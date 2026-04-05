import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var inputWindowController: InputWindowController?

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
            self?.statusItemController?.taskManager.submit(prompt: prompt)
        }

        // 监听 TaskManager 变化，更新菜单栏图标
        statusItemController?.startObserving()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
