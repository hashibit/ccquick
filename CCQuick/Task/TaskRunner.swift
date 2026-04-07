import Foundation

enum TaskRunnerError: Error {
    case claudeNotFound
    case launchFailed(Error)
}

class TaskRunner {

    static func findClaudePath() -> String? {
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/claude",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        // fallback: which claude
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["claude"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (result?.isEmpty == false) ? result : nil
    }

    // onOutput: 流式输出回调（主线程调用）
    // onComplete: 任务结束回调（主线程调用）
    static func run(
        task: CCTask,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (CCTask) -> Void
    ) {
        guard let claudePath = findClaudePath() else {
            var failed = task
            failed.status = .failed
            failed.response = "找不到 claude CLI。请确认已通过 npm install -g @anthropic-ai/claude-code 安装并在 PATH 中。"
            failed.finishedAt = .now
            Task { @MainActor in onComplete(failed) }
            return
        }

        let workDir = URL(fileURLWithPath: task.workDir)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--dangerously-skip-permissions", "-p", task.prompt]
        process.currentDirectoryURL = workDir

        // 设置环境变量
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(env["PATH"] ?? "")"

        // 根据执行账户类型设置环境变量
        let settings = AppSettings.current
        if settings.executionAccount == .codingPlan {
            // CodingPlan 订阅：使用配置的厂商
            let apiKey = settings.codingPlanApiKey.trimmingCharacters(in: .whitespaces)
            if !apiKey.isEmpty {
                // 根据 API key 匹配厂商，使用第一个匹配的
                let providers = CodingPlanProvider.matchProviders(for: apiKey)
                if let provider = providers.first {
                    env["ANTHROPIC_BASE_URL"] = provider.baseURL
                    env["ANTHROPIC_MODEL"] = provider.model
                    env["ANTHROPIC_AUTH_TOKEN"] = apiKey
                }
            }
        }
        // 默认 Claude 订阅：不设置额外环境变量，使用 CLI 默认配置

        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var buffer = ""

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer += text
            Task { @MainActor in onOutput(text) }
        }

        process.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            // 读取剩余数据
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: remaining, encoding: .utf8), !text.isEmpty {
                buffer += text
            }
            var completed = task
            completed.response = buffer
            completed.finishedAt = .now
            completed.status = (p.terminationStatus == 0) ? .completed : .failed
            Task { @MainActor in onComplete(completed) }
        }

        do {
            try process.run()
        } catch {
            var failed = task
            failed.status = .failed
            failed.response = "启动失败：\(error.localizedDescription)"
            failed.finishedAt = .now
            Task { @MainActor in onComplete(failed) }
        }
    }
}
