import Foundation
import Carbon
import SwiftUI

// MARK: - 日志管理器

@MainActor
class LogManager: ObservableObject {
    static let shared = LogManager()

    @Published var logs: [LogEntry] = []

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let category: String
        let message: String

        var formattedTime: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter.string(from: timestamp)
        }
    }

    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"

        var color: Color {
            switch self {
            case .debug: return .gray
            case .info: return .primary
            case .warning: return .orange
            case .error: return .red
            }
        }
    }

    private init() {}

    func debug(_ message: String, category: String = "App") { addLog(level: .debug, category: category, message: message) }
    func info(_ message: String, category: String = "App") { addLog(level: .info, category: category, message: message) }
    func warning(_ message: String, category: String = "App") { addLog(level: .warning, category: category, message: message) }
    func error(_ message: String, category: String = "App") { addLog(level: .error, category: category, message: message) }

    private func addLog(level: LogLevel, category: String, message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, category: category, message: message)
        logs.append(entry)
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
        print("[\(level.rawValue)][\(category)] \(message)")
    }

    func clear() { logs.removeAll() }
}

func logDebug(_ message: String, category: String = "App") { Task { @MainActor in LogManager.shared.debug(message, category: category) } }
func logInfo(_ message: String, category: String = "App") { Task { @MainActor in LogManager.shared.info(message, category: category) } }
func logWarning(_ message: String, category: String = "App") { Task { @MainActor in LogManager.shared.warning(message, category: category) } }
func logError(_ message: String, category: String = "App") { Task { @MainActor in LogManager.shared.error(message, category: category) } }

// MARK: - 执行账户类型
enum ExecutionAccount: String, Codable, CaseIterable {
    case claudeSubscription = "claude"
    case codingPlan = "coding_plan"

    var displayName: String {
        switch self {
        case .claudeSubscription: return "默认 Claude 订阅"
        case .codingPlan: return "CodingPlan 订阅"
        }
    }
}

// CodingPlan 厂商配置
struct CodingPlanProvider: Codable {
    let name: String
    let baseURL: String
    let model: String
    let keyPrefixes: [String]

    static let providers: [CodingPlanProvider] = [
        CodingPlanProvider(name: "Kimi", baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k", keyPrefixes: ["sk-"]),
        CodingPlanProvider(name: "通义千问", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-turbo", keyPrefixes: ["sk-"]),
        CodingPlanProvider(name: "DeepSeek", baseURL: "https://api.deepseek.com", model: "deepseek-chat", keyPrefixes: ["sk-"]),
        CodingPlanProvider(name: "智谱", baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4", keyPrefixes: ["."]),
        CodingPlanProvider(name: "百炼", baseURL: "https://coding.dashscope.aliyuncs.com/apps/anthropic", model: "kimi-k2.5", keyPrefixes: ["sk-sp-"]),
    ]

    static func matchProviders(for apiKey: String) -> [CodingPlanProvider] {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return providers }

        var matched: [(provider: CodingPlanProvider, score: Int)] = []
        for provider in providers {
            for prefix in provider.keyPrefixes {
                if trimmed.hasPrefix(prefix) {
                    matched.append((provider, prefix.count))
                    break
                }
            }
        }
        matched.sort { $0.score > $1.score }
        return matched.isEmpty ? providers : matched.map { $0.provider }
    }
}

// 可用性检测器
@MainActor
class AvailabilityChecker: ObservableObject {
    @Published var isChecking = false
    @Published var result: CheckResult?

    struct CheckResult {
        let success: Bool
        let message: String
        let providerName: String?
    }

    func checkClaudeSubscription() async -> CheckResult {
        isChecking = true
        defer { isChecking = false }

        logInfo("开始检测 Claude 订阅...", category: "Check")

        // 查找 claude 路径
        let claudePath = findClaudePath()
        logDebug("Claude 路径: \(claudePath ?? "未找到")", category: "Check")

        guard let path = claudePath else {
            let result = CheckResult(success: false, message: "未找到 Claude CLI，请先安装", providerName: nil)
            self.result = result
            logError("未找到 Claude CLI", category: "Check")
            return result
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--dangerously-skip-permissions", "-p", "Say ok"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            logDebug("启动进程: \(path)", category: "Check")
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""

            logDebug("Exit code: \(process.terminationStatus)", category: "Check")
            logDebug("Output: \(output.prefix(200))", category: "Check")
            if !error.isEmpty { logWarning("Stderr: \(error.prefix(200))", category: "Check") }

            if process.terminationStatus == 0 {
                let result = CheckResult(success: true, message: "可用", providerName: "Claude CLI")
                self.result = result
                logInfo("Claude CLI 检测成功", category: "Check")
                return result
            } else {
                let result = CheckResult(success: false, message: "失败: \(error.prefix(100))", providerName: nil)
                self.result = result
                logError("Claude CLI 检测失败: \(error.prefix(100))", category: "Check")
                return result
            }
        } catch {
            logError("启动失败: \(error)", category: "Check")
            let result = CheckResult(success: false, message: "启动失败: \(error.localizedDescription)", providerName: nil)
            self.result = result
            return result
        }
    }

    func checkCodingPlan(apiKey: String) async -> CheckResult {
        isChecking = true
        defer { isChecking = false }

        logInfo("开始检测 CodingPlan...", category: "Check")

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else {
            let result = CheckResult(success: false, message: "请输入 API Key", providerName: nil)
            self.result = result
            logWarning("API Key 为空", category: "Check")
            return result
        }

        let providers = CodingPlanProvider.matchProviders(for: trimmedKey)
        logInfo("匹配到 \(providers.count) 个厂商: \(providers.map { $0.name }.joined(separator: ", "))", category: "Check")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ccquick-check")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var lastError = ""
        for provider in providers {
            logDebug("尝试厂商: \(provider.name)", category: "Check")
            let result = await checkProvider(provider: provider, apiKey: trimmedKey, tempDir: tempDir)
            if result.success {
                self.result = result
                logInfo("检测成功: \(provider.name)", category: "Check")
                return result
            }
            lastError = result.message
        }

        let result = CheckResult(success: false, message: "全部失败: \(lastError)", providerName: nil)
        self.result = result
        logError("所有厂商检测失败", category: "Check")
        return result
    }

    private func checkProvider(provider: CodingPlanProvider, apiKey: String, tempDir: URL) async -> CheckResult {
        return await withCheckedContinuation { continuation in
            let claudePath = findClaudePath()

            guard let path = claudePath else {
                logError("未找到 Claude CLI", category: "Check")
                continuation.resume(returning: CheckResult(success: false, message: "未找到 Claude CLI", providerName: nil))
                return
            }

            let process = Process()
            process.currentDirectoryURL = tempDir

            var env = ProcessInfo.processInfo.environment
            env["ANTHROPIC_BASE_URL"] = provider.baseURL
            env["ANTHROPIC_MODEL"] = provider.model
            env["ANTHROPIC_AUTH_TOKEN"] = apiKey
            process.environment = env

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--dangerously-skip-permissions", "-p", "Say ok"]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let error = String(data: errorData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    logInfo("\(provider.name) 检测成功", category: "Check")
                    continuation.resume(returning: CheckResult(success: true, message: "可用", providerName: provider.name))
                } else {
                    logWarning("\(provider.name) 失败: \(error.prefix(100))", category: "Check")
                    continuation.resume(returning: CheckResult(success: false, message: "\(provider.name): \(error.prefix(50))", providerName: provider.name))
                }
            } catch {
                logError("启动失败: \(error)", category: "Check")
                continuation.resume(returning: CheckResult(success: false, message: "启动失败", providerName: nil))
            }
        }
    }

    private nonisolated func findClaudePath() -> String? {
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/claude",
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // 尝试用 which 查找
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        if let data = try? pipe.fileHandleForReading.readToEnd(),
           let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }

        return nil
    }
}

struct AppSettings: Codable {
    var executionAccount: ExecutionAccount = .claudeSubscription
    var codingPlanApiKey: String = ""
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

    // 快捷键显示字符串
    static var hotkeyDisplayString: String {
        let s = current
        var parts: [String] = []

        if s.hotkeyModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if s.hotkeyModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if s.hotkeyModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if s.hotkeyModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }

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
    var executionAccount: ExecutionAccount
    var codingPlanApiKey: String
    var hotkeyModifiers: UInt32
    var hotkeyKeyCode: UInt32

    static let shared = SettingsStore()

    private init() {
        let s = AppSettings.current
        executionAccount = s.executionAccount
        codingPlanApiKey = s.codingPlanApiKey
        hotkeyModifiers = s.hotkeyModifiers
        hotkeyKeyCode = s.hotkeyKeyCode
    }

    func save() {
        AppSettings.save(AppSettings(
            executionAccount: executionAccount,
            codingPlanApiKey: codingPlanApiKey,
            hotkeyModifiers: hotkeyModifiers,
            hotkeyKeyCode: hotkeyKeyCode
        ))
        InputWindowController.shared.updateHotkey()
    }

    var hotkeyDisplayString: String {
        AppSettings.hotkeyDisplayString
    }
}