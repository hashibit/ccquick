import Foundation
import UserNotifications

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    var onTaskNotificationClicked: ((String) -> Void)?

    private override init() {}

    func notify(task: CCTask) {
        let content = UNMutableNotificationContent()
        content.title = task.status == .completed ? "✓ 任务完成" : "✗ 任务失败"
        content.body = task.shortPrompt
        content.sound = .default
        content.userInfo = ["taskId": task.id]

        let request = UNNotificationRequest(
            identifier: task.id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // 用户点击通知时触发
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let taskId = response.notification.request.content.userInfo["taskId"] as? String ?? ""
        DispatchQueue.main.async {
            self.onTaskNotificationClicked?(taskId)
        }
        completionHandler()
    }

    // 应用在前台时也显示通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
