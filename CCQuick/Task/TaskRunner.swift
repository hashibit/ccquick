import Foundation

enum TaskRunnerError: Error {
    case claudeNotFound
    case launchFailed(Error)
}

/// Thread-safe controller for a running Claude CLI process.
class ProcessController {
    private let process: Process
    private let lock = NSLock()
    private var stoppedByUser = false

    init(process: Process) {
        self.process = process
    }

    /// Terminate the process. Returns true on first call, false if already stopped.
    @discardableResult
    func stop() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !stoppedByUser else { return false }
        stoppedByUser = true

        let pid = process.processIdentifier

        // Step 1: Send SIGINT (Ctrl+C) — Claude CLI handles this gracefully
        kill(-pid, SIGINT)

        // Step 2: If still running after 2s, force-kill the entire process group
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(2)) { [weak self, weak process] in
            guard let process = process, process.isRunning else { return }
            kill(-pid, SIGKILL)
        }

        // Step 3: Final fallback — NSProcess.terminate() after 5s
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(5)) { [weak process] in
            guard let process = process, process.isRunning else { return }
            process.terminate()
        }

        return true
    }

    /// Called from the terminationHandler to determine if user initiated the stop.
    func isStoppedByUser() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stoppedByUser
    }
}

class TaskRunner {

    // MARK: - Tool Call Parsing

    /// 从流式输出中解析并记录工具调用
    static func parseAndLogToolCalls(_ text: String, taskId: String) {
        let toolPatterns = ["Tool use:", "Using tool:", "⏺ ", "◯ "]
        for pattern in toolPatterns {
            if text.contains(pattern) {
                for line in text.components(separatedBy: "\n") where line.contains(pattern) {
                    let toolInfo = line.replacingOccurrences(of: pattern, with: "").trimmingCharacters(in: .whitespaces)
                    if !toolInfo.isEmpty {
                        logTool("▸ \(toolInfo)", category: taskId)
                    }
                }
            }
        }

        let toolNames = ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "WebFetch", "WebSearch"]
        for tool in toolNames {
            if text.contains("\(tool)(") || text.contains("tool: \(tool)"),
               let range = text.range(of: "\(tool)(") {
                let rest = text[range.upperBound...]
                if let endRange = rest.range(of: ")") {
                    let params = String(rest[..<endRange.lowerBound])
                    let summary = extractParamSummary(tool: tool, params: params)
                    let suffix = summary.isEmpty ? "" : " \(summary)"
                    logTool("▸ \(tool)\(suffix)", category: taskId)
                } else {
                    logTool("▸ \(tool)", category: taskId)
                }
            }
        }
    }

    private static func extractParamSummary(tool: String, params: String) -> String {
        switch tool {
        case "Read", "Write", "Edit", "Glob", "Grep":
            if let path = extractPathFromParams(params) {
                return path.components(separatedBy: "/").last ?? path
            }
        case "Bash":
            if let cmdMatch = params.components(separatedBy: "command").first {
                let cmd = cmdMatch.components(separatedBy: "=").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                if let cmd = cmd, !cmd.isEmpty {
                    return cmd.prefix(50).description
                }
            }
        default:
            break
        }
        return ""
    }

    private static func extractPathFromParams(_ params: String) -> String? {
        if let pathMatch = params.components(separatedBy: "file_path").first {
            let pathPart = pathMatch.components(separatedBy: "=").last?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
            if let path = pathPart, !path.isEmpty { return path }
        }
        let pathPatterns = params.components(separatedBy: "\"").filter { $0.contains("/") }
        return pathPatterns.first
    }

    // MARK: - Claude Path Detection

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

    // MARK: - Public API

    /// 直接执行
    static func run(
        task: CCTask,
        prompt: String,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (CCTask) -> Void,
        onControllerCreated: @escaping (ProcessController) -> Void = { _ in }
    ) {
        _execute(
            task: task,
            prompt: prompt,
            logLabel: "Claude CLI Session",
            parseToolCalls: true,
            onOutput: onOutput,
            onComplete: onComplete,
            onControllerCreated: onControllerCreated
        )
    }

    /// 带计划执行
    static func runWithPlan(
        task: CCTask,
        plan: String,
        userPrompt: String,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (CCTask) -> Void,
        onControllerCreated: @escaping (ProcessController) -> Void = { _ in }
    ) {
        let workDir = URL(fileURLWithPath: task.workDir)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

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

        let enhancedPrompt = """
        用户请求：\(userPrompt)

        建议的执行计划：
        \(plan)

        请按照这个计划执行。
        """

        _execute(
            task: task,
            prompt: enhancedPrompt,
            logLabel: "Claude CLI Session (带计划执行)",
            parseToolCalls: true,
            onOutput: onOutput,
            onComplete: onComplete,
            onControllerCreated: onControllerCreated
        )
    }

    /// 追问执行
    static func runFollowUp(
        task: CCTask,
        followUpPrompt: String,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (CCTask) -> Void,
        onControllerCreated: @escaping (ProcessController) -> Void = { _ in }
    ) {
        _execute(
            task: task,
            prompt: followUpPrompt,
            logLabel: "Claude CLI Session (追问)",
            parseToolCalls: false,
            onOutput: onOutput,
            onComplete: onComplete,
            continueSession: true,
            onControllerCreated: onControllerCreated
        )
    }

    // MARK: - Internal Execution Engine

    private static func _execute(
        task: CCTask,
        prompt: String,
        logLabel: String,
        parseToolCalls: Bool,
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (CCTask) -> Void,
        continueSession: Bool = false,
        onControllerCreated: @escaping (ProcessController) -> Void = { _ in }
    ) {
        guard let claudePath = findClaudePath() else {
            failTask(task, message: "找不到 claude CLI。请确认已通过 npm install -g @anthropic-ai/claude-code 安装并在 PATH 中。", onComplete: onComplete)
            return
        }

        let workDir = URL(fileURLWithPath: task.workDir)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let env = buildEnvironment()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--dangerously-skip-permissions"]
        if continueSession {
            process.arguments?.append("--continue")
        }
        process.arguments?.append(contentsOf: ["-p", prompt])
        process.currentDirectoryURL = workDir
        process.environment = env

        logAI("""
        🖥️ \(logLabel)
        - Claude Path: \(claudePath)
        - 执行账户: \(AppSettings.current.executionAccount.displayName)
        - Model: \(env["ANTHROPIC_MODEL"] ?? "默认")
        - Base URL: \(env["ANTHROPIC_BASE_URL"] ?? "默认")
        - Arguments: \(process.arguments ?? [])
        """, category: "CLI")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var buffer = ""

        let controller = ProcessController(process: process)
        onControllerCreated(controller)

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer += text
            if parseToolCalls {
                parseAndLogToolCalls(text, taskId: task.id)
            }
            Task { @MainActor in onOutput(text) }
        }

        process.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: remaining, encoding: .utf8), !text.isEmpty {
                buffer += text
            }
            try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                type: .assistant, content: buffer
            ))
            var completed = task
            completed.finishedAt = .now
            if controller.isStoppedByUser() {
                completed.status = .stopped
            } else {
                completed.status = (p.terminationStatus == 0) ? .completed : .failed
            }
            Task { @MainActor in onComplete(completed) }
        }

        do {
            try process.run()
        } catch {
            try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
                type: .assistant, content: "启动失败：\(error.localizedDescription)"
            ))
            var failed = task
            failed.status = .failed
            failed.finishedAt = .now
            Task { @MainActor in onComplete(failed) }
        }
    }

    // MARK: - Helpers

    private static func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(env["PATH"] ?? "")"

        let settings = AppSettings.current
        if settings.executionAccount == .codingPlan {
            let apiKey = settings.codingPlanApiKey.trimmingCharacters(in: .whitespaces)
            if !apiKey.isEmpty,
               let provider = CodingPlanProvider.matchProviders(for: apiKey).first {
                env["ANTHROPIC_BASE_URL"] = provider.baseURL
                env["ANTHROPIC_MODEL"] = provider.sonnetModel
                env["ANTHROPIC_AUTH_TOKEN"] = apiKey
            }
        }
        return env
    }

    private static func failTask(
        _ task: CCTask,
        message: String,
        onComplete: @escaping (CCTask) -> Void
    ) {
        try? TaskStore.shared.appendMessage(id: task.id, message: SessionMessage(
            type: .assistant, content: message
        ))
        var failed = task
        failed.status = .failed
        failed.finishedAt = .now
        Task { @MainActor in onComplete(failed) }
    }
}
