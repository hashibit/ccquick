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
}
