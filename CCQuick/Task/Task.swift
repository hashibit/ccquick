import Foundation

enum TaskStatus: String, Codable {
    case running
    case completed
    case failed
}

struct CCTask: Identifiable, Codable, Hashable {
    let id: String
    let prompt: String
    let workDir: String
    var status: TaskStatus
    let startedAt: Date
    var finishedAt: Date?
    var response: String
    var viewed: Bool

    var shortPrompt: String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 40 ? String(trimmed.prefix(40)) + "…" : trimmed
    }

    var elapsedSeconds: Int {
        Int((finishedAt ?? .now).timeIntervalSince(startedAt))
    }

    var elapsedString: String {
        let s = elapsedSeconds
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
