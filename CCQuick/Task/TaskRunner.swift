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
            failed.finishedAt = Date()
            DispatchQueue.main.async { onComplete(failed) }
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

        // 注入用户配置的 API 设置
        let settings = AppSettings.current
        if !settings.apiBase.isEmpty {
            env["ANTHROPIC_BASE_URL"] = settings.apiBase
        }
        if !settings.apiKey.isEmpty {
            env["ANTHROPIC_AUTH_TOKEN"] = settings.apiKey
        }
        if !settings.model.isEmpty {
            env["ANTHROPIC_MODEL"] = settings.model
        }

        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var buffer = ""

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer += text
            DispatchQueue.main.async { onOutput(text) }
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
            completed.finishedAt = Date()
            completed.status = (p.terminationStatus == 0) ? .completed : .failed
            DispatchQueue.main.async { onComplete(completed) }
        }

        do {
            try process.run()
        } catch {
            var failed = task
            failed.status = .failed
            failed.response = "启动失败：\(error.localizedDescription)"
            failed.finishedAt = Date()
            DispatchQueue.main.async { onComplete(failed) }
        }
    }
}
