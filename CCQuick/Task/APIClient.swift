import Foundation

// MARK: - API 客户端

class APIClient {

    /// 带 Tool Call 的执行循环（Anthropic 兼容 API）
    static func executeWithTools(
        prompt: String,
        provider: CodingPlanProvider,
        apiKey: String,
        workDir: String
    ) async throws -> String {
        // 动态发现已安装的 skills（渐进式披露第一层）
        let skillsDescription = SkillRegistry.installedSkillsDescription()
        let systemPrompt = """
        你是一个智能助手，通过调用工具来完成任务。

        重要规则：
        - 所有文件操作（Bash/Read/Write）都限制在工作目录内：\(workDir)
        - 不要读取或修改工作目录以外的任何文件
        - Bash 命令应始终在当前目录或其子目录中操作

        已安装的 skills 列表如下。当用户的请求匹配某个 skill 的描述时，使用 Skill 工具加载其完整指令后再执行：
        \(skillsDescription)
        """

        var messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]

        let maxToolUseRounds = 20

        for round in 0..<maxToolUseRounds {
            logAI("━━━━━━━━ 第 \(round + 1) 轮 ━━━━━━━━", category: "API")

            let (data, response) = try await sendAnthropicRequest(
                messages: messages,
                provider: provider,
                apiKey: apiKey,
                systemPrompt: systemPrompt
            )

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIClientError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIClientError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
            }

            let contentBlocks = try parseContentBlocks(data: data)

            // 提取 assistant 文本
            var assistantText = ""
            for block in contentBlocks where block["type"] as? String == "text" {
                assistantText += (block["text"] as? String) ?? ""
            }

            // 提取 tool_use 块
            let toolUseBlocks = contentBlocks.filter { $0["type"] as? String == "tool_use" }

            if toolUseBlocks.isEmpty {
                // 没有工具调用，返回最终文本
                if assistantText.isEmpty {
                    assistantText = "（无输出）"
                }
                logAI("最终响应 (\(assistantText.utf8.count) 字符): \(assistantText.prefix(100))...", category: "API")
                return assistantText
            }

            logAI("🛠️ 发现 \(toolUseBlocks.count) 个工具调用:", category: "API")
            for tu in toolUseBlocks {
                logAI("  - \(tu["name"] as? String ?? "unknown") (id: \(tu["id"] as? String ?? "nil"))", category: "API")
            }

            // 执行所有工具调用
            var toolResults: [[String: Any]] = []
            for toolUse in toolUseBlocks {
                let toolId = (toolUse["id"] as? String) ?? ""
                let toolName = (toolUse["name"] as? String) ?? ""
                let input = toolUse["input"] as? [String: Any] ?? [:]

                let output: String
                let isError: Bool

                do {
                    output = try ToolExecutor.execute(name: toolName, input: input, workDir: workDir)
                    isError = false
                } catch {
                    output = error.localizedDescription
                    isError = true
                    logTool("✗ \(toolName) 失败: \(error.localizedDescription)", category: "API")
                }

                toolResults.append([
                    "type": "tool_result",
                    "tool_use_id": toolId,
                    "content": [["type": "text", "text": output]],
                    "is_error": isError
                ])
            }

            // 构建 tool_result 消息
            messages.append([
                "role": "assistant",
                "content": contentBlocks
            ])
            messages.append([
                "role": "user",
                "content": toolResults
            ])

            if !assistantText.isEmpty {
                logDebug("Assistant 中间响应: \(assistantText.prefix(100))", category: "API")
            }
        }

        throw APIClientError.maxToolUseRounds
    }

    // MARK: - HTTP 请求

    private static func sendAnthropicRequest(
        messages: [[String: Any]],
        provider: CodingPlanProvider,
        apiKey: String,
        systemPrompt: String
    ) async throws -> (Data, URLResponse) {
        let tools: [[String: Any]] = [
            [
                "name": "Bash",
                "description": "Execute a shell command and return the output",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "command": ["type": "string", "description": "The shell command to execute"]
                    ],
                    "required": ["command"]
                ]
            ],
            [
                "name": "Read",
                "description": "Read the contents of a file. Only files within the working directory can be accessed.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "file_path": ["type": "string", "description": "Path to the file to read"]
                    ],
                    "required": ["file_path"]
                ]
            ],
            [
                "name": "Write",
                "description": "Write content to a file. Only files within the working directory can be created.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "file_path": ["type": "string", "description": "Path to the file to write"],
                        "content": ["type": "string", "description": "Content to write to the file"]
                    ],
                    "required": ["file_path", "content"]
                ]
            ],
            [
                "name": "Skill",
                "description": "Load the full instructions for an installed skill by name. Use this when the user's request matches a skill's description.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "The exact name of the skill to load"]
                    ],
                    "required": ["name"]
                ]
            ]
        ]

        let url = URL(string: "\(provider.baseURL)/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch provider.authType {
        case .xApiKey:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(env["PATH"] ?? "")"

        let body: [String: Any] = [
            "model": provider.sonnetModel,
            "max_tokens": 8192,
            "system": systemPrompt,
            "messages": messages,
            "tools": tools
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        return try await URLSession.shared.data(for: request)
    }

    // MARK: - Response Parsing

    private static func parseContentBlocks(data: Data) throws -> [[String: Any]] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIClientError.invalidJSON
        }

        guard let contentArray = json["content"] as? [[String: Any]] else {
            throw APIClientError.invalidContent
        }

        return contentArray
    }
}

// MARK: - 错误类型

enum APIClientError: Error, LocalizedError {
    case invalidResponse
    case invalidJSON
    case invalidContent
    case httpError(statusCode: Int, message: String)
    case maxToolUseRounds

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "无效的响应"
        case .invalidJSON:
            return "无效的 JSON 格式"
        case .invalidContent:
            return "无法解析响应内容"
        case .httpError(let statusCode, let message):
            return "HTTP 错误 \(statusCode): \(message)"
        case .maxToolUseRounds:
            return "工具调用轮数超过上限"
        }
    }
}

// MARK: - Tool Executor

private enum ToolExecutor {
    static func execute(name: String, input: [String: Any], workDir: String) throws -> String {
        logTool("🔧 调用工具: \(name), 参数: \(input.keys.joined(separator: ", "))", category: "Tool")
        let start = CFAbsoluteTimeGetCurrent()

        let output: String
        switch name {
        case "Bash":
            output = try executeBash(command: input["command"] as? String ?? "", workDir: workDir)
        case "Read":
            output = try executeRead(filePath: input["file_path"] as? String ?? "", workDir: workDir)
        case "Write":
            output = try executeWrite(filePath: input["file_path"] as? String ?? "", content: input["content"] as? String ?? "", workDir: workDir)
        case "Skill":
            output = try executeSkill(name: input["name"] as? String ?? "")
        default:
            throw ToolError.unknownTool(name)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let size = output.utf8.count
        logTool("✓ \(name) 完成 (耗时: \(String(format: "%.2f", elapsed))s, 输出: \(size) 字符)", category: "Tool")
        return output
    }

    private static func executeBash(command: String, workDir: String) throws -> String {
        logTool("▸ bash> \(command.prefix(200))", category: "Tool")

        // 命令预检查：拒绝访问工作目录之外的路径
        try validateCommand(command, workDir: workDir)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workDir)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            logTool("⚠ bash 退出码: \(process.terminationStatus)", category: "Tool")
        }

        var result = stdout
        if !stderr.isEmpty {
            if !result.isEmpty { result += "\n" }
            result += stderr
        }
        if result.isEmpty {
            result = "(命令执行完成，无输出)"
        }

        return result
    }

    /// 命令预检查：拒绝访问工作目录之外的用户路径
    private static func validateCommand(_ command: String, workDir: String) throws {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        // 拒绝 ~ 或 $HOME 开头的路径
        let homeAccessPatterns = [
            "~/",
            "~ ",
            "$HOME",
            homeDir,
            "/Users/\(NSUserName())",
        ]

        for pattern in homeAccessPatterns where command.contains(pattern) {
            // 允许 workDir 本身
            if workDir.hasPrefix(pattern) {
                continue
            }
            throw ToolError.commandBlocked("命令尝试访问用户主目录: \(command.prefix(100))")
        }

        // 拒绝 /Users/ 下非 workDir 的路径
        if command.contains("/Users/") {
            let userPathRegex = try NSRegularExpression(pattern: "/Users/[^\\s'\"]+")
            let matches = userPathRegex.matches(in: command, range: NSRange(command.startIndex..., in: command))
            for match in matches {
                if let range = Range(match.range, in: command) {
                    let path = String(command[range])
                    if !path.hasPrefix(workDir) {
                        throw ToolError.commandBlocked("命令尝试访问用户目录: \(path)")
                    }
                }
            }
        }
    }

    private static func executeRead(filePath: String, workDir: String) throws -> String {
        logTool("▸ read \(filePath)", category: "Tool")
        let resolvedPath = try resolvePath(filePath, workDir: workDir)
        let content = try String(contentsOfFile: resolvedPath, encoding: .utf8)
        logTool("  → 已读取 (\(content.utf8.count) 字符)", category: "Tool")
        return content
    }

    private static func executeWrite(filePath: String, content: String, workDir: String) throws -> String {
        logTool("▸ write \(filePath) (\(content.utf8.count) 字符)", category: "Tool")
        let resolvedPath = try resolvePath(filePath, workDir: workDir)
        let dir = (resolvedPath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            logTool("  → 创建目录: \(dir)", category: "Tool")
        }
        try content.write(toFile: resolvedPath, atomically: true, encoding: .utf8)
        logTool("  → 已写入", category: "Tool")
        return "已写入: \(filePath)"
    }

    private static func executeSkill(name: String) throws -> String {
        logTool("▸ skill: \(name)", category: "Tool")
        let skillPath = SkillRegistry.skillsDir().appendingPathComponent(name).appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: skillPath.path) else {
            throw ToolError.skillNotFound(name)
        }
        let content = try String(contentsOfFile: skillPath.path, encoding: .utf8)
        logTool("  → 已加载 (\(content.utf8.count) 字符)", category: "Tool")
        return content
    }

    private static func resolvePath(_ path: String, workDir: String) throws -> String {
        var resolved = path
        if !resolved.hasPrefix("/") {
            resolved = (workDir as NSString).appendingPathComponent(path)
        }
        resolved = (resolved as NSString).standardizingPath

        let workDirResolved = (workDir as NSString).standardizingPath
        guard resolved.hasPrefix(workDirResolved + "/") || resolved == workDirResolved else {
            throw ToolError.pathOutsideSandbox(path)
        }

        return resolved
    }
}

private enum ToolError: Error, LocalizedError {
    case unknownTool(String)
    case pathOutsideSandbox(String)
    case skillNotFound(String)
    case commandBlocked(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "未知工具: \(name)"
        case .pathOutsideSandbox(let path):
            return "路径超出工作目录限制: \(path)"
        case .skillNotFound(let name):
            return "Skill 未找到: \(name)"
        case .commandBlocked(let reason):
            return "命令被拒绝: \(reason)"
        }
    }
}

// MARK: - Skill Registry

private enum SkillRegistry {

    static func skillsDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("skills")
    }

    /// 扫描已安装的 skills，返回名称+描述列表
    static func installedSkillsDescription() -> String {
        let skillsDir = skillsDir()
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: skillsDir.path) else {
            return "（无已安装 skill）"
        }

        var lines: [String] = []
        for name in items.sorted() {
            let skillMd = skillsDir.appendingPathComponent(name).appendingPathComponent("SKILL.md")
            if let content = try? String(contentsOfFile: skillMd.path, encoding: .utf8),
               let desc = extractDescription(from: content) {
                lines.append("- \(name): \(desc)")
            }
        }

        return lines.isEmpty ? "（无已安装 skill）" : lines.joined(separator: "\n")
    }

    /// 从 SKILL.md frontmatter 提取 description
    private static func extractDescription(from content: String) -> String? {
        guard content.hasPrefix("---") else { return nil }
        let parts = content.dropFirst(3).split(separator: "---", maxSplits: 1)
        guard parts.count >= 2 else { return nil }

        let frontmatter = String(parts[0])
        // 匹配 description: 或 description: >\n
        let patterns = [
            #"(?m)^description:\s*(.+)$"#,
            #"(?m)^description:\s*>\s*\n\s*(.+)$"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: frontmatter, range: NSRange(frontmatter.startIndex..., in: frontmatter)) {
                let range = match.range(at: 1)
                if let swiftRange = Range(range, in: frontmatter) {
                    let desc = String(frontmatter[swiftRange]).trimmingCharacters(in: .whitespaces)
                    // 合并多行
                    return desc.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                }
            }
        }
        return nil
    }
}
