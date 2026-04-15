import Foundation

final class OpenAIClient: AIProviderClient {
    let provider: AIProvider = .openai
    let modelId: String
    private(set) var inputTokensUsed: Int = 0
    private(set) var outputTokensUsed: Int = 0

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private var tools: [[String: Any]] = []
    private var messages: [[String: Any]] = []

    init(modelId: String) {
        self.modelId = modelId
    }

    func start(systemPrompt: String, initialUserMessage: String, tools: [AITool], maxTokens: Int) async throws -> AIProviderResponse {
        self.tools = tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.inputSchema
                ]
            ]
        }
        self.messages = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": initialUserMessage]
        ]
        return try await send(maxTokens: maxTokens)
    }

    func continueConversation(toolResults: [AIToolResult], maxTokens: Int) async throws -> AIProviderResponse {
        // OpenAI: 각 tool result는 개별 role="tool" 메시지
        for r in toolResults {
            messages.append([
                "role": "tool",
                "tool_call_id": r.id,
                "content": r.content
            ])
        }
        return try await send(maxTokens: maxTokens)
    }

    private func send(maxTokens: Int) async throws -> AIProviderResponse {
        let key = try loadKey()
        var body: [String: Any] = [
            "model": modelId,
            "messages": messages,
            "max_completion_tokens": maxTokens,
        ]
        if !tools.isEmpty { body["tools"] = tools }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse("non-HTTP") }
        guard (200..<300).contains(http.statusCode) else {
            throw AIProviderError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.decodingFailed("not json")
        }
        guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first,
              let msg = first["message"] as? [String: Any]
        else { throw AIProviderError.decodingFailed("no choices/message") }

        let stopReason = (first["finish_reason"] as? String) ?? ""
        let text = (msg["content"] as? String) ?? ""

        var toolUses: [AIToolUse] = []
        if let toolCalls = msg["tool_calls"] as? [[String: Any]] {
            for call in toolCalls {
                guard let id = call["id"] as? String,
                      let fn = call["function"] as? [String: Any],
                      let name = fn["name"] as? String else { continue }
                let argsStr = (fn["arguments"] as? String) ?? "{}"
                let input = (try? JSONSerialization.jsonObject(with: argsStr.data(using: .utf8) ?? Data()) as? [String: Any]) ?? [:]
                toolUses.append(AIToolUse(id: id, name: name, input: input))
            }
        }

        // 다음 턴을 위해 assistant 메시지 누적 (원본 그대로 포함 — null content도 보존)
        var assistantMsg: [String: Any] = ["role": "assistant"]
        assistantMsg["content"] = msg["content"] ?? NSNull()
        if let tc = msg["tool_calls"] { assistantMsg["tool_calls"] = tc }
        messages.append(assistantMsg)

        if let usage = obj["usage"] as? [String: Any] {
            inputTokensUsed += (usage["prompt_tokens"] as? Int) ?? 0
            outputTokensUsed += (usage["completion_tokens"] as? Int) ?? 0
        }

        return AIProviderResponse(
            text: text,
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
