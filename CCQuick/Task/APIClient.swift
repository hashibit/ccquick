import Foundation

// MARK: - 第一阶段响应

struct FirstStageResponse {
    let canAnswerDirectly: Bool
    let answer: String?
    let plan: String?
}

// MARK: - API 客户端

class APIClient {

    /// 第一阶段：询问 LLM 是否能快速回答
    static func ask(
        prompt: String,
        provider: CodingPlanProvider,
        apiKey: String
    ) async throws -> FirstStageResponse {
        let systemPrompt = """
        你是一个智能助手，负责判断用户请求的处理方式。

        判断规则：
        - 如果这是一个你能快速回答的问题（如：查询信息、简单计算、概念解释、代码片段等），直接给出答案
        - 如果这需要多步骤执行、涉及文件操作、需要访问外部资源等，给出一个简短的执行计划

        你必须严格按照以下 JSON 格式回复，不要有任何其他内容：
        {"type": "answer", "content": "你的回答内容"}
        或
        {"type": "plan", "content": "执行计划的简短描述"}
        """

        let url: URL
        var request: URLRequest

        switch provider.apiType {
        case .anthropic:
            url = URL(string: "\(provider.baseURL)/v1/messages")!
        case .openai:
            url = URL(string: "\(provider.baseURL)/chat/completions")!
        }

        request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch provider.authType {
        case .xApiKey:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // 构建请求体
        let body: [String: Any]
        switch provider.apiType {
        case .anthropic:
            body = [
                "model": provider.haikuModel,
                "max_tokens": 2048,
                "system": systemPrompt,
                "messages": [["role": "user", "content": prompt]]
            ]
        case .openai:
            body = [
                "model": provider.haikuModel,
                "max_tokens": 2048,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": prompt]
                ]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        // 记录 AI 调用详情
        logAI("""
        📡 HTTP 直接请求
        - Provider: \(provider.name)
        - URL: \(url.absoluteString)
        - Model: \(provider.haikuModel)
        - API Type: \(provider.apiType.rawValue)
        - Auth Type: \(provider.authType.rawValue)
        """, category: "API")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logError("API 错误 HTTP \(httpResponse.statusCode): \(errorBody)", category: "API")
            throw APIClientError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // 解析响应
        return try parseResponse(data: data, apiType: provider.apiType)
    }

    /// 解析 API 响应
    private static func parseResponse(data: Data, apiType: CodingPlanProvider.APIType) throws -> FirstStageResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIClientError.invalidJSON
        }

        // 提取 content
        var content: String?

        switch apiType {
        case .anthropic:
            // Anthropic 格式: {"content": [{"type": "text", "text": "..."}]}
            if let contentArray = json["content"] as? [[String: Any]],
               let firstContent = contentArray.first,
               let text = firstContent["text"] as? String {
                content = text
            }
        case .openai:
            // OpenAI 格式: {"choices": [{"message": {"content": "..."}}]}
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let text = message["content"] as? String {
                content = text
            }
        }

        guard let content = content else {
            logError("无法解析响应内容: \(json)", category: "API")
            throw APIClientError.invalidContent
        }

        logDebug("第一阶段响应: \(content.prefix(100))...", category: "API")

        // 解析 JSON 格式的回复
        return try parseFirstStageContent(content)
    }

    /// 解析第一阶段的内容
    private static func parseFirstStageContent(_ content: String) throws -> FirstStageResponse {
        // 尝试提取 JSON
        let jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 尝试找到 JSON 对象
        guard let startIndex = jsonString.firstIndex(of: "{"),
              let endIndex = jsonString.lastIndex(of: "}") else {
            // 没有 JSON，当作直接回答
            return FirstStageResponse(canAnswerDirectly: true, answer: content, plan: nil)
        }

        let jsonSubstring = jsonString[startIndex...endIndex]
        guard let jsonData = String(jsonSubstring).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] else {
            // 无法解析 JSON，当作直接回答
            return FirstStageResponse(canAnswerDirectly: true, answer: content, plan: nil)
        }

        guard let type = json["type"], let contentValue = json["content"] else {
            // 缺少必要字段，当作直接回答
            return FirstStageResponse(canAnswerDirectly: true, answer: content, plan: nil)
        }

        if type == "answer" {
            return FirstStageResponse(canAnswerDirectly: true, answer: contentValue, plan: nil)
        } else if type == "plan" {
            return FirstStageResponse(canAnswerDirectly: false, answer: nil, plan: contentValue)
        } else {
            // 未知类型，当作直接回答
            return FirstStageResponse(canAnswerDirectly: true, answer: content, plan: nil)
        }
    }
}

// MARK: - 错误类型

enum APIClientError: Error, LocalizedError {
    case invalidResponse
    case invalidJSON
    case invalidContent
    case httpError(statusCode: Int, message: String)

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
        }
    }
}