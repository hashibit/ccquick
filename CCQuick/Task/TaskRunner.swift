import Foundation

enum TaskRunnerError: Error {
    case claudeNotFound
    case launchFailed(Error)
}

class TaskRunner {

    // MARK: - 工具调用解析

    /// 从流式输出中解析并记录工具调用
    private static func parseAndLogToolCalls(_ text: String, taskId: String) {
        // 检测常见工具调用标记
        let toolPatterns = [
            "Tool use:",
            "Using tool:",
            "⏺ ",
            "◯ ",
        ]

        for pattern in toolPatterns {
            if text.contains(pattern) {
                let lines = text.components(separatedBy: "\n")
                for line in lines where line.contains(pattern) {
                    let toolInfo = line.replacingOccurrences(of: pattern, with: "").trimmingCharacters(in: .whitespaces)
                    if !toolInfo.isEmpty {
                        logTool("▸ \(toolInfo)", category: taskId)
                    }
                }
            }
        }

        let toolNames = ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "WebFetch", "WebSearch"]
        for tool in toolNames {
            if text.contains("\(tool)(") || text.contains("tool: \(tool)") {
                if let range = text.range(of: "\(tool)(") {
                    let start = range.upperBound
                    let rest = text[start...]
                    if let endRange = rest.range(of: ")") {
                        let params = String(rest[..<endRange.lowerBound])
                        let summary = extractParamSummary(tool: tool, params: params)
                        logTool("▸ \(tool) \(summary)", category: taskId)
                    } else {
                        logTool("▸ \(tool)", category: taskId)
                    }
                }
            }
        }
    }

    private static func extractParamSummary(tool: String, params: String) -> String {
        switch tool {
        case "Read", "Write", "Edit", "Glob", "Grep":
            if let pathMatch = params.components(separatedBy: "file_path").first {
                let pathPart = pathMatch.components(separatedBy: "=").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                if let path = pathPart, !path.isEmpty {
                    return path.components(separatedBy: "/").last ?? path
                }
            }
            let pathPatterns = params.components(separatedBy: "\"").filter { $0.contains("/") }
            if let path = pathPatterns.first {
                return path.components(separatedBy: "/").last ?? path
            }
        case "Bash":
            if let cmdMatch = params.components(separatedBy: "command").first {
                let cmdPart = cmdMatch.components(separatedBy: "=").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                if let cmd = cmdPart, !cmd.isEmpty {
                    return cmd.prefix(50).description
                }
            }
        default:
            break
        }
        return ""
    }

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

    /// 带计划的执行（第二阶段）
    static func runWithPlan(
        task: CCTask,
        plan: String,
        userPrompt: String,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (CCTask) -> Void
    ) {
        guard let claudePath = findClaudePath() else {
            var failed = task
            failed.status = .failed
            failed.finishedAt = .now
            // 写入错误消息到 session.jsonl
            try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                type: .assistant,
                content: "找不到 claude CLI。请确认已通过 npm install -g @anthropic-ai/claude-code 安装并在 PATH 中。"
            ))
            Task { @MainActor in onComplete(failed) }
            return
        }

        let workDir = URL(fileURLWithPath: task.workDir)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        // 写入初始上下文文件
        let contextContent = """
        # 任务

        \(userPrompt)

        # 执行计划

        \(plan)

        请按照执行计划逐步完成任务。
        """
        let contextFile = workDir.appendingPathComponent("initial_context.md")
        try? contextContent.write(to: contextFile, atomically: true, encoding: .utf8)
        logInfo("写入初始上下文: \(contextFile.path)", category: "Task")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)

        // 构建带计划的 prompt
        let enhancedPrompt = """
        用户请求：\(userPrompt)

        建议的执行计划：
        \(plan)

        请按照这个计划执行任务。
        """
        process.arguments = ["--dangerously-skip-permissions", "-p", enhancedPrompt]
        process.currentDirectoryURL = workDir

        // 设置环境变量
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(env["PATH"] ?? "")"

        let settings = AppSettings.current
        if settings.executionAccount == .codingPlan {
            let apiKey = settings.codingPlanApiKey.trimmingCharacters(in: .whitespaces)
            if !apiKey.isEmpty {
                let providers = CodingPlanProvider.matchProviders(for: apiKey)
                if let provider = providers.first {
                    env["ANTHROPIC_BASE_URL"] = provider.baseURL
                    env["ANTHROPIC_MODEL"] = provider.sonnetModel
                    env["ANTHROPIC_AUTH_TOKEN"] = apiKey
                }
            }
        }

        process.environment = env

        let modelInfo = env["ANTHROPIC_MODEL"] ?? "默认"
        let baseUrlInfo = env["ANTHROPIC_BASE_URL"] ?? "默认"
        logAI("""
        🖥️ Claude CLI Session (带计划执行)
        - Claude Path: \(claudePath)
        - 执行账户: \(settings.executionAccount.displayName)
        - Model: \(modelInfo)
        - Base URL: \(baseUrlInfo)
        - Arguments: \(process.arguments ?? [])
        """, category: "CLI")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var buffer = ""

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer += text
            parseAndLogToolCalls(text, taskId: task.id)
            Task { @MainActor in onOutput(text) }
        }

        process.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: remaining, encoding: .utf8), !text.isEmpty {
                buffer += text
            }
            // 写入 assistant 消息到 session.jsonl
            try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                type: .assistant,
                content: buffer
            ))
            var completed = task
            completed.finishedAt = .now
            completed.status = (p.terminationStatus == 0) ? .completed : .failed
            Task { @MainActor in onComplete(completed) }
        }

        do {
            try process.run()
        } catch {
            try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                type: .assistant,
                content: "启动失败：\(error.localizedDescription)"
            ))
            var failed = task
            failed.status = .failed
            failed.finishedAt = .now
            Task { @MainActor in onComplete(failed) }
        }
    }

    // MARK: - 直接执行
    static func run(
        task: CCTask,
        prompt: String,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (CCTask) -> Void
    ) {
        guard let claudePath = findClaudePath() else {
            var failed = task
            failed.status = .failed
            failed.finishedAt = .now
            try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                type: .assistant,
                content: "找不到 claude CLI。请确认已通过 npm install -g @anthropic-ai/claude-code 安装并在 PATH 中。"
            ))
            Task { @MainActor in onComplete(failed) }
            return
        }

        let workDir = URL(fileURLWithPath: task.workDir)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--dangerously-skip-permissions", "-p", prompt]
        process.currentDirectoryURL = workDir

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(env["PATH"] ?? "")"

        let settings = AppSettings.current
        if settings.executionAccount == .codingPlan {
            let apiKey = settings.codingPlanApiKey.trimmingCharacters(in: .whitespaces)
            if !apiKey.isEmpty {
                let providers = CodingPlanProvider.matchProviders(for: apiKey)
                if let provider = providers.first {
                    env["ANTHROPIC_BASE_URL"] = provider.baseURL
                    env["ANTHROPIC_MODEL"] = provider.sonnetModel
                    env["ANTHROPIC_AUTH_TOKEN"] = apiKey
                }
            }
        }

        process.environment = env

        let modelInfo = env["ANTHROPIC_MODEL"] ?? "默认"
        let baseUrlInfo = env["ANTHROPIC_BASE_URL"] ?? "默认"
        logAI("""
        🖥️ Claude CLI Session
        - Claude Path: \(claudePath)
        - 执行账户: \(settings.executionAccount.displayName)
        - Model: \(modelInfo)
        - Base URL: \(baseUrlInfo)
        - Arguments: \(process.arguments ?? [])
        """, category: "CLI")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var buffer = ""

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer += text
            parseAndLogToolCalls(text, taskId: task.id)
            Task { @MainActor in onOutput(text) }
        }

        process.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: remaining, encoding: .utf8), !text.isEmpty {
                buffer += text
            }
            // 写入 assistant 消息到 session.jsonl
            try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                type: .assistant,
                content: buffer
            ))
            var completed = task
            completed.finishedAt = .now
            completed.status = (p.terminationStatus == 0) ? .completed : .failed
            Task { @MainActor in onComplete(completed) }
        }

        do {
            try process.run()
        } catch {
            try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                type: .assistant,
                content: "启动失败：\(error.localizedDescription)"
            ))
            var failed = task
            failed.status = .failed
            failed.finishedAt = .now
            Task { @MainActor in onComplete(failed) }
        }
    }

    // MARK: - 追问执行
    static func runFollowUp(
        task: CCTask,
        followUpPrompt: String,
        contextPrompt: String,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (CCTask) -> Void
    ) {
        guard let claudePath = findClaudePath() else {
            try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                type: .assistant,
                content: "追问失败：找不到 claude CLI"
            ))
            var failed = task
            failed.status = .failed
            failed.finishedAt = .now
            Task { @MainActor in onComplete(failed) }
            return
        }

        let workDir = URL(fileURLWithPath: task.workDir)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--dangerously-skip-permissions", "-p", contextPrompt]
        process.currentDirectoryURL = workDir

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(env["PATH"] ?? "")"

        let settings = AppSettings.current
        if settings.executionAccount == .codingPlan {
            let apiKey = settings.codingPlanApiKey.trimmingCharacters(in: .whitespaces)
            if !apiKey.isEmpty {
                let providers = CodingPlanProvider.matchProviders(for: apiKey)
                if let provider = providers.first {
                    env["ANTHROPIC_BASE_URL"] = provider.baseURL
                    env["ANTHROPIC_MODEL"] = provider.sonnetModel
                    env["ANTHROPIC_AUTH_TOKEN"] = apiKey
                }
            }
        }

        process.environment = env

        let modelInfo = env["ANTHROPIC_MODEL"] ?? "默认"
        let baseUrlInfo = env["ANTHROPIC_BASE_URL"] ?? "默认"
        logAI("""
        🖥️ Claude CLI Session (追问)
        - Claude Path: \(claudePath)
        - 执行账户: \(settings.executionAccount.displayName)
        - Model: \(modelInfo)
        - Base URL: \(baseUrlInfo)
        - Arguments: \(process.arguments ?? [])
        """, category: "CLI")

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
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: remaining, encoding: .utf8), !text.isEmpty {
                buffer += text
            }
            // 写入 assistant 消息到 session.jsonl
            try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                type: .assistant,
                content: buffer
            ))
            var completed = task
            completed.finishedAt = .now
            completed.status = (p.terminationStatus == 0) ? .completed : .failed
            Task { @MainActor in onComplete(completed) }
        }

        do {
            try process.run()
        } catch {
            try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                type: .assistant,
                content: "追问启动失败：\(error.localizedDescription)"
            ))
            var failed = task
            failed.status = .failed
            failed.finishedAt = .now
            Task { @MainActor in onComplete(failed) }
        }
    }
}