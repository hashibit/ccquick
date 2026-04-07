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
    let apiType: APIType
    let authType: AuthType

    enum APIType: String, Codable {
        case anthropic  // Anthropic 兼容 API (路径: /v1/messages)
        case openai     // OpenAI 兼容 API (路径: /chat/completions)
    }

    enum AuthType: String, Codable {
        case xApiKey    // Anthropic 原生: x-api-key header
        case bearer     // OpenAI 风格: Authorization: Bearer
    }

    static let providers: [CodingPlanProvider] = [
        // Anthropic 兼容 API，Bearer 认证
        CodingPlanProvider(name: "百炼", baseURL: "https://coding.dashscope.aliyuncs.com/apps/anthropic", model: "qwen3-coder-plus", keyPrefixes: ["sk-sp-"], apiType: .anthropic, authType: .bearer),
        // OpenAI 兼容 API
        CodingPlanProvider(name: "Kimi", baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k", keyPrefixes: ["sk-"], apiType: .openai, authType: .bearer),
        CodingPlanProvider(name: "通义千问", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-turbo", keyPrefixes: ["sk-"], apiType: .openai, authType: .bearer),
        CodingPlanProvider(name: "DeepSeek", baseURL: "https://api.deepseek.com", model: "deepseek-chat", keyPrefixes: ["sk-"], apiType: .openai, authType: .bearer),
        CodingPlanProvider(name: "智谱", baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash", keyPrefixes: ["."], apiType: .openai, authType: .bearer),
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

        // 只返回最长匹配的厂商，避免测试不相关的 API
        if let best = matched.first {
            return [best.provider]
        }
        return providers
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

    struct ProviderCheckResult {
        let provider: CodingPlanProvider
        let success: Bool
        let error: String?
        let duration: TimeInterval
    }

    func checkClaudeSubscription() {
        isChecking = true
        result = nil

        // Claude 订阅不需要检测，直接显示成功
        logInfo("使用 Claude CLI 默认配置", category: "Check")
        isChecking = false
        result = CheckResult(success: true, message: "使用 Claude CLI 配置", providerName: "Claude CLI")
    }

    func checkCodingPlan(apiKey: String) {
        isChecking = true
        result = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            let checkResult = await self?.runCodingPlanCheck(apiKey: apiKey)
            await MainActor.run {
                self?.isChecking = false
                if let r = checkResult { self?.result = r }
            }
        }
    }

    private nonisolated func runCodingPlanCheck(apiKey: String) async -> CheckResult {
        logInfo("开始并行检测 CodingPlan...", category: "Check")

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else {
            logWarning("API Key 为空", category: "Check")
            return CheckResult(success: false, message: "请输入 API Key", providerName: nil)
        }

        let providers = CodingPlanProvider.matchProviders(for: trimmedKey)
        logInfo("并行测试 \(providers.count) 个厂商", category: "Check")

        // 并行测试所有厂商
        let results = await withTaskGroup(of: ProviderCheckResult.self) { group in
            for provider in providers {
                group.addTask {
                    await self.testProviderAPI(provider: provider, apiKey: trimmedKey)
                }
            }

            var allResults: [ProviderCheckResult] = []
            for await result in group {
                allResults.append(result)
                if result.success {
                    // 找到成功的，取消其他请求
                    group.cancelAll()
                    break
                }
            }
            return allResults
        }

        // 找第一个成功的结果
        for result in results where result.success {
            logInfo("检测成功: \(result.provider.name), 耗时: \(String(format: "%.2f", result.duration))s", category: "Check")
            return CheckResult(success: true, message: "可用 (\(String(format: "%.2f", result.duration))s)", providerName: result.provider.name)
        }

        // 全部失败
        let failedProviders = results.filter { !$0.success }.map { "\($0.provider.name): \($0.error ?? "未知错误")" }.joined(separator: "; ")
        logError("所有厂商检测失败", category: "Check")
        return CheckResult(success: false, message: failedProviders, providerName: nil)
    }

    private nonisolated func testProviderAPI(provider: CodingPlanProvider, apiKey: String) async -> ProviderCheckResult {
        let startTime = Date()

        let url: URL
        var request: URLRequest

        // 根据 apiType 决定路径
        switch provider.apiType {
        case .anthropic:
            url = URL(string: "\(provider.baseURL)/v1/messages")!
        case .openai:
            url = URL(string: "\(provider.baseURL)/chat/completions")!
        }

        request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 根据 authType 决定认证方式
        switch provider.authType {
        case .xApiKey:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // 请求体格式相同
        let body: [String: Any] = [
            "model": provider.model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "Hi"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        logDebug("测试 \(provider.name) (\(provider.apiType.rawValue))", category: "Check")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince(startTime)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    logInfo("\(provider.name) 成功 (\(String(format: "%.2f", duration))s)", category: "Check")
                    return ProviderCheckResult(provider: provider, success: true, error: nil, duration: duration)
                } else {
                    logWarning("\(provider.name) HTTP \(httpResponse.statusCode)", category: "Check")
                    return ProviderCheckResult(provider: provider, success: false, error: "HTTP \(httpResponse.statusCode)", duration: duration)
                }
            }
            return ProviderCheckResult(provider: provider, success: false, error: "无响应", duration: Date().timeIntervalSince(startTime))
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logWarning("\(provider.name) \(error.localizedDescription)", category: "Check")
            return ProviderCheckResult(provider: provider, success: false, error: error.localizedDescription, duration: duration)
        }
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