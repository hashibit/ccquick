import Foundation

class TaskStore {
    static let shared = TaskStore()

    let baseDir: URL

    private static let idFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmm"
        return f
    }()

    private init() {
        baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ccquick")
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    // MARK: - Task Meta

    func save(_ task: CCTask) throws {
        let dir = baseDir.appendingPathComponent(task.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(task)
        try data.write(to: dir.appendingPathComponent("meta.json"))
    }

    func load(id: String) -> CCTask? {
        let metaURL = baseDir.appendingPathComponent(id).appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CCTask.self, from: data)
    }

    func loadAll() -> [CCTask] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return contents.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")) else { return nil }
            return try? decoder.decode(CCTask.self, from: data)
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    func makeTaskId(prompt: String) -> String {
        let timestamp = Self.idFormatter.string(from: .now)
        let slug = prompt
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .prefix(30)
        return "\(timestamp)-\(slug.isEmpty ? "task" : String(slug))"
    }

    func delete(id: String) {
        let dir = baseDir.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Session Messages (JSONL)

    private func sessionFileURL(id: String) -> URL {
        baseDir.appendingPathComponent(id).appendingPathComponent("session.jsonl")
    }

    /// 追加写入一条消息到 session.jsonl
    func appendMessage(id: String, message: SessionMessage) throws {
        let fileURL = sessionFileURL(id: id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)
        // JSONL: 每行一个 JSON，追加写入
        var line = String(data: data, encoding: .utf8)!
        line += "\n"
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let existing = try String(contentsOf: fileURL, encoding: .utf8)
            try (existing + line).write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            try line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    /// 更新最后一条 assistant 消息的内容（流式输出完成时）
    func updateLastAssistantMessage(id: String, content: String) throws {
        let messages = loadMessages(id: id)
        guard let lastIdx = messages.indices.last,
              messages[lastIdx].type == .assistant else { return }

        var updated = messages
        updated[lastIdx] = SessionMessage(
            type: .assistant,
            content: content,
            timestamp: messages[lastIdx].timestamp,
            isStreaming: false
        )
        try writeAllMessages(id: id, messages: updated)
    }

    /// 重写所有消息（用于更新）
    func writeAllMessages(id: String, messages: [SessionMessage]) throws {
        let fileURL = sessionFileURL(id: id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var lines: [String] = []
        for msg in messages {
            let data = try encoder.encode(msg)
            lines.append(String(data: data, encoding: .utf8)!)
        }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// 读取所有消息
    func loadMessages(id: String) -> [SessionMessage] {
        let fileURL = sessionFileURL(id: id)
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return text.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> SessionMessage? in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(SessionMessage.self, from: lineData)
            }
    }

    /// 获取第一条 user 消息（用于显示标题）
    func getFirstPrompt(id: String) -> String? {
        loadMessages(id: id).first(where: { $0.type == .user })?.content
    }

    /// 获取最后一条 assistant 消息（用于预览）
    func getLastResponse(id: String) -> String? {
        loadMessages(id: id).last(where: { $0.type == .assistant })?.content
    }

    /// 获取任务的显示标题（从第一条 user 消息截取）
    func getShortPrompt(id: String) -> String {
        guard let prompt = getFirstPrompt(id: id) else { return "任务" }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed
    }
}
