import Foundation

enum TaskRunnerError: Error {
    case claudeNotFound
    case launchFailed(Error)
}

class TaskRunner {

    // MARK: - 工具调用解析

    /// 从流式输出中解析并记录工具调用
    private static func parseAndLogToolCalls(_ text: String, taskId: String) {
        // Claude CLI 输出格式中工具调用可能以多种形式出现
        // 1. "---" 分隔后跟随工具信息
        // 2. "Tool use:" 或 "Using tool:" 标记
        // 3. JSON 格式的工具调用块

        // 检测常见工具调用标记
        let toolPatterns = [
            "Tool use:",
            "Using tool:",
            "⏺ ",  // Claude CLI 的工具标记
            "◯ ",   // 另一种标记
        ]

        for pattern in toolPatterns {
            if text.contains(pattern) {
                // 提取工具行
                let lines = text.components(separatedBy: "\n")
                for line in lines where line.contains(pattern) {
                    let toolInfo = line.replacingOccurrences(of: pattern, with: "").trimmingCharacters(in: .whitespaces)
                    if !toolInfo.isEmpty {
                        logTool("▸ \(toolInfo)", category: taskId)
                    }
                }
            }
        }

        // 检测特定工具名称（Read, Write, Bash, Glob, Grep 等）
        let toolNames = ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "WebFetch", "WebSearch"]
        for tool in toolNames {
            if text.contains("\(tool)(") || text.contains("tool: \(tool)") {
                // 尝试提取参数摘要
                if let range = text.range(of: "\(tool)(") {
                    let start = range.upperBound
                    let rest = text[start...]
                    if let endRange = rest.range(of: ")") {
                        let params = String(rest[..<endRange.lowerBound])
                        // 截取关键参数
                        let summary = extractParamSummary(tool: tool, params: params)
                        logTool("▸ \(tool) \(summary)", category: taskId)
                    } else {
                        logTool("▸ \(tool)", category: taskId)
                    }
                }
            }
        }
    }

    /// 提取参数摘要（如文件路径、命令等关键信息）
    private static func extractParamSummary(tool: String, params: String) -> String {
        switch tool {
        case "Read", "Write", "Edit", "Glob", "Grep":
            // 提取文件路径
            if let pathMatch = params.components(separatedBy: "file_path").first {
                let pathPart = pathMatch.components(separatedBy: "=").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                if let path = pathPart, !path.isEmpty {
                    // 只显示文件名或相对路径
                    return path.components(separatedBy: "/").last ?? path
                }
            }
            // 尝试直接匹配路径格式
            let pathPatterns = params.components(separatedBy: "\"").filter { $0.contains("/") }
            if let path = pathPatterns.first {
                return path.components(separatedBy: "/").last ?? path
            }
        case "Bash":
            // 提取命令
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

    /// 带计划的执行（第二阶段）
    /// - Parameters:
    ///   - task: 任务
    ///   - plan: 第一阶段生成的执行计划
    ///   - onOutput: 流式输出回调
    ///   - onComplete: 任务结束回调
    static func runWithPlan(
        task: CCTask,
        plan: String,
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

        // 写入初始上下文文件
        let contextContent = """
        # 任务

        \(task.prompt)

        # 执行计划

        \(plan)

        请按照执行计划逐步完成任务。
        """
        let contextFile = workDir.appendingPathComponent("initial_context.md")
        try? contextContent.write(to: contextFile, atomically: true, encoding: .utf8)
        logInfo("写入初始上下文: \(contextFile.path)", category: "Task")

        // 写入 prompt 文件
        let promptFile = workDir.appendingPathComponent("prompt.txt")
        try? task.prompt.write(to: promptFile, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)

        // 构建带计划的 prompt
        let enhancedPrompt = """
        用户请求：\(task.prompt)

        建议的执行计划：
        \(plan)

        请按照这个计划执行任务。
        """
        process.arguments = ["--dangerously-skip-permissions", "-p", enhancedPrompt]
        process.currentDirectoryURL = workDir

        // 设置环境变量
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(env["PATH"] ?? "")"

        // 根据执行账户类型设置环境变量
        let settings = AppSettings.current
        if settings.executionAccount == .codingPlan {
            let apiKey = settings.codingPlanApiKey.trimmingCharacters(in: .whitespaces)
            if !apiKey.isEmpty {
                let providers = CodingPlanProvider.matchProviders(for: apiKey)
                if let provider = providers.first {
                    env["ANTHROPIC_BASE_URL"] = provider.baseURL
                    env["ANTHROPIC_MODEL"] = provider.sonnetModel  // 复杂任务用 sonnet
                    env["ANTHROPIC_AUTH_TOKEN"] = apiKey
                }
            }
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
            // 解析并记录工具调用
            parseAndLogToolCalls(text, taskId: task.id)
            Task { @MainActor in onOutput(text) }
        }

        process.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
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
                    env["ANTHROPIC_MODEL"] = provider.sonnetModel
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
            // 解析并记录工具调用
            parseAndLogToolCalls(text, taskId: task.id)
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

    /// 追问执行：在同一个任务目录中继续对话
    /// 追问的输出会追加到之前的 response，用分隔符区分不同轮次
    static func runFollowUp(
        task: CCTask,
        originalPrompt: String,
        originalResponse: String,
        followUpPrompt: String,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (CCTask) -> Void
    ) {
        guard let claudePath = findClaudePath() else {
            var failed = task
            failed.status = .failed
            failed.response = originalResponse + "\n\n---\n\n**追问失败：找不到 claude CLI**"
            failed.finishedAt = .now
            Task { @MainActor in onComplete(failed) }
            return
        }

        let workDir = URL(fileURLWithPath: task.workDir)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)

        // 构建追问 prompt（包含历史上下文）
        let followUpContext = """
        【历史对话】
        原始需求：\(originalPrompt)

        之前的回复：
        \(originalResponse)

        ---
        【追问】\(followUpPrompt)

        请继续回答，注意保持上下文连贯。
        """
        process.arguments = ["--dangerously-skip-permissions", "-p", followUpContext]
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

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var newResponse = ""

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            newResponse += text
            Task { @MainActor in onOutput(text) }
        }

        process.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: remaining, encoding: .utf8), !text.isEmpty {
                newResponse += text
            }

            // 追问的结果追加到之前的 response
            var completed = task
            let separator = "\n\n---\n\n### 追问：\(followUpPrompt)\n\n"
            completed.response = originalResponse + separator + newResponse
            completed.finishedAt = .now
            completed.status = (p.terminationStatus == 0) ? .completed : .failed
            Task { @MainActor in onComplete(completed) }
        }

        do {
            try process.run()
        } catch {
            var failed = task
            failed.status = .failed
            failed.response = originalResponse + "\n\n---\n\n**追问启动失败：\(error.localizedDescription)**"
            failed.finishedAt = .now
            Task { @MainActor in onComplete(failed) }
        }
    }
}
