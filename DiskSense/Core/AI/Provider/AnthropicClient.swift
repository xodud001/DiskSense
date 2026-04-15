import Foundation

final class AnthropicClient: AIProviderClient {
    let provider: AIProvider = .anthropic
    let modelId: String
    private(set) var inputTokensUsed: Int = 0
    private(set) var outputTokensUsed: Int = 0

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private var systemPrompt: String = ""
    private var tools: [[String: Any]] = []
    private var messages: [[String: Any]] = []

    init(modelId: String) {
        self.modelId = modelId
    }

    func start(systemPrompt: String, initialUserMessage: String, tools: [AITool], maxTokens: Int) async throws -> AIProviderResponse {
        self.systemPrompt = systemPrompt
        self.tools = tools.map { [
            "name": $0.name,
            "description": $0.description,
            "input_schema": $0.inputSchema
        ] }
        self.messages = [["role": "user", "content": initialUserMessage]]
        return try await send(maxTokens: maxTokens)
    }

    func continueConversation(toolResults: [AIToolResult], maxTokens: Int) async throws -> AIProviderResponse {
        let content: [[String: Any]] = toolResults.map {
            [
                "type": "tool_result",
                "tool_use_id": $0.id,
                "content": $0.content,
                "is_error": $0.isError
            ]
        }
        messages.append(["role": "user", "content": content])
        return try await send(maxTokens: maxTokens)
    }

    private func send(maxTokens: Int) async throws -> AIProviderResponse {
        let key = try loadKey()
        var body: [String: Any] = [
            "model": modelId,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": messages,
        ]
        if !tools.isEmpty { body["tools"] = tools }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse("non-HTTP") }
        guard (200..<300).contains(http.statusCode) else {
            throw AIProviderError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.decodingFailed("not json")
        }
        let stopReason = obj["stop_reason"] as? String ?? ""
        let content = obj["content"] as? [[String: Any]] ?? []

        var textParts: [String] = []
        var toolUses: [AIToolUse] = []
        for block in content {
            let type = block["type"] as? String
            if type == "text", let t = block["text"] as? String {
                textParts.append(t)
            } else if type == "tool_use",
                      let id = block["id"] as? String,
                      let name = block["name"] as? String {
                let input = (block["input"] as? [String: Any]) ?? [:]
                toolUses.append(AIToolUse(id: id, name: name, input: input))
            }
        }

        // 다음 턴을 위해 assistant 메시지 누적 (raw content 그대로)
        messages.append(["role": "assistant", "content": content])

        if let usage = obj["usage"] as? [String: Any] {
            inputTokensUsed += (usage["input_tokens"] as? Int) ?? 0
            outputTokensUsed += (usage["output_tokens"] as? Int) ?? 0
        }

        return AIProviderResponse(
            text: textParts.joined(separator: "\n"),
            toolUses: toolUses,
            stopReason: stopReason,
            inputTokens: inputTokensUsed,
            outputTokens: outputTokensUsed
        )
    }

    private func loadKey() throws -> String {
        do { return try KeychainHelper.retrieve(key: provider.keychainKey) }
        catch { throw AIProviderError.missingKey(provider) }
    }
}
