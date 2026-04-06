import Foundation

struct AppSettings: Codable {
    var apiBase: String = "https://api.anthropic.com"
    var apiKey: String = ""
    var model: String = "claude-sonnet-4-20250514"

    private static let fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ccquick")
        .appendingPathComponent("settings.json")

    static var current: AppSettings = load()

    private static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }

    static func save(_ settings: AppSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL)
        current = settings
    }

    static var hasApiKey: Bool {
        !current.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// ObservableObject 包装，供 SwiftUI 绑定
@MainActor
@Observable
class SettingsStore {
    var apiBase: String
    var apiKey: String
    var model: String

    static let shared = SettingsStore()

    private init() {
        let s = AppSettings.current
        apiBase = s.apiBase
        apiKey = s.apiKey
        model = s.model
    }

    func save() {
        AppSettings.save(AppSettings(
            apiBase: apiBase,
            apiKey: apiKey,
            model: model
        ))
    }
}