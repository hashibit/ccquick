import Foundation
import UserNotifications

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    var onTaskNotificationClicked: ((String) -> Void)?

    private override init() {}

    func notify(task: CCTask) {
        let content = UNMutableNotificationContent()
        // 问题作为 title，答案作为 body，不设置 subtitle
        content.title = task.shortPrompt
        content.body = shortResponse(task.response)
        content.sound = .default
        content.userInfo = ["taskId": task.id]

        let request = UNNotificationRequest(
            identifier: task.id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// 截取答案的前 120 字符，去掉 Markdown 格式标记
    private func shortResponse(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉常见 Markdown 格式
        var clean = trimmed
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "```", with: "")  // 多次确保去掉
            .replacingOccurrences(of: "---", with: "")
            .replacingOccurrences(of: "- ", with: "• ")
        return clean.count > 120 ? String(clean.prefix(120)) + "…" : clean
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
