import Foundation
import UserNotifications

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    var onTaskNotificationClicked: ((String) -> Void)?

    private override init() {}

    func notify(task: CCTask, response: String? = nil) {
        let content = UNMutableNotificationContent()

        // 从 session.jsonl 读取消息
        let messages = TaskStore.shared.loadMessages(id: task.id)

        // 找到最后一条 user 消息和 assistant 消息
        let lastUserMsg = messages.last(where: { $0.type == .user })
        let lastAssistantMsg = messages.last(where: { $0.type == .assistant })

        if let userMsg = lastUserMsg {
            content.title = String(userMsg.content.prefix(80))
        } else {
            content.title = L10n.notificationCompleted
        }

        if let assistantMsg = lastAssistantMsg {
            content.body = shortResponse(assistantMsg.content)
        } else if let resp = response {
            content.body = shortResponse(resp)
        } else {
            content.body = L10n.notificationCompletedBody
        }

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
        var clean = trimmed
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "```", with: "")
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