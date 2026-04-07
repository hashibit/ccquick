import Foundation
import Carbon

struct AppSettings: Codable {
    var apiBase: String = "https://api.anthropic.com"
    var apiKey: String = ""
    var model: String = "claude-sonnet-4-20250514"
    var hotkeyModifiers: UInt32 = UInt32(cmdKey | shiftKey)
    var hotkeyKeyCode: UInt32 = 36 // Return/Enter

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

    // 快捷键显示字符串
    static var hotkeyDisplayString: String {
        let s = current
        var parts: [String] = []

        if s.hotkeyModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if s.hotkeyModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if s.hotkeyModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if s.hotkeyModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }

        // keyCode 映射
        let keyName: String
        switch s.hotkeyKeyCode {
        case 36: keyName = "Enter"
        case 49: keyName = "Space"
        case 48: keyName = "Tab"
        case 51: keyName = "Delete"
        case 53: keyName = "Esc"
        case 0: keyName = "A"
        case 1: keyName = "S"
        case 2: keyName = "D"
        case 3: keyName = "F"
        case 4: keyName = "H"
        case 5: keyName = "G"
        case 6: keyName = "Z"
        case 7: keyName = "X"
        case 8: keyName = "C"
        case 9: keyName = "V"
        case 11: keyName = "B"
        case 12: keyName = "Q"
        case 13: keyName = "W"
        case 14: keyName = "E"
        case 15: keyName = "R"
        case 16: keyName = "Y"
        case 17: keyName = "T"
        case 18: keyName = "1"
        case 19: keyName = "2"
        case 20: keyName = "3"
        case 21: keyName = "4"
        case 22: keyName = "6"
        case 23: keyName = "5"
        case 24: keyName = "="
        case 25: keyName = "9"
        case 26: keyName = "7"
        case 27: keyName = "-"
        case 28: keyName = "8"
        case 29: keyName = "0"
        case 30: keyName = "]"
        case 31: keyName = "O"
        case 32: keyName = "U"
        case 33: keyName = "["
        case 34: keyName = "I"
        case 35: keyName = "P"
        case 37: keyName = "L"
        case 38: keyName = "J"
        case 39: keyName = "'"
        case 40: keyName = "K"
        case 41: keyName = ";"
        case 42: keyName = "\\"
        case 43: keyName = ","
        case 44: keyName = "/"
        case 45: keyName = "N"
        case 46: keyName = "M"
        case 47: keyName = "."
        case 50: keyName = "`"
        default: keyName = "Key\(s.hotkeyKeyCode)"
        }

        parts.append(keyName)
        return parts.joined()
    }
}

// ObservableObject 包装，供 SwiftUI 绑定
@MainActor
@Observable
class SettingsStore {
    var apiBase: String
    var apiKey: String
    var model: String
    var hotkeyModifiers: UInt32
    var hotkeyKeyCode: UInt32

    static let shared = SettingsStore()

    private init() {
        let s = AppSettings.current
        apiBase = s.apiBase
        apiKey = s.apiKey
        model = s.model
        hotkeyModifiers = s.hotkeyModifiers
        hotkeyKeyCode = s.hotkeyKeyCode
    }

    func save() {
        AppSettings.save(AppSettings(
            apiBase: apiBase,
            apiKey: apiKey,
            model: model,
            hotkeyModifiers: hotkeyModifiers,
            hotkeyKeyCode: hotkeyKeyCode
        ))
        // 更新快捷键
        InputWindowController.shared.updateHotkey()
    }

    var hotkeyDisplayString: String {
        AppSettings.hotkeyDisplayString
    }
}