import Foundation

enum TaskStatus: String, Codable {
    case running
    case completed
    case failed
    case stopped
}

struct CCTask: Identifiable, Codable, Hashable {
    let id: String
    let workDir: String
    var status: TaskStatus
    let startedAt: Date
    var finishedAt: Date?
    var viewed: Bool

    var elapsedSeconds: Int {
        Int((finishedAt ?? .now).timeIntervalSince(startedAt))
    }

    var elapsedString: String {
        let s = elapsedSeconds
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// session.jsonl 中的消息结构
enum MessageType: String, Codable {
    case user
    case assistant
}

struct SessionMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let type: MessageType
    let content: String
    let timestamp: Date
    var isStreaming: Bool = false

    init(type: MessageType, content: String, timestamp: Date = .now, isStreaming: Bool = false) {
        self.id = UUID()
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}
