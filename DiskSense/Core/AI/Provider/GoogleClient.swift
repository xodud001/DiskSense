import Foundation

final class GoogleClient: AIProviderClient {
    let provider: AIProvider = .google
    let modelId: String
    private(set) var inputTokensUsed: Int = 0
    private(set) var outputTokensUsed: Int = 0

    private var systemInstruction: [String: Any] = [:]
    private var tools: [[String: Any]] = []
    private var contents: [[String: Any]] = []

    init(modelId: String) {
        self.modelId = modelId
    }

    private func endpointURL(key: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelId):generateContent?key=\(key)")!
    }

    func start(systemPrompt: String, initialUserMessage: String, tools: [AITool], maxTokens: Int) async throws -> AIProviderResponse {
        self.systemInstruction = ["parts": [["text": systemPrompt]]]
        let declarations = tools.map { tool -> [String: Any] in
            [
                "name": tool.name,
                "description": tool.description,
                "parameters": Self.convertSchemaForGemini(tool.inputSchema)
            ]
        }
        self.tools = [["functionDeclarations": declarations]]
        self.contents = [
            ["role": "user", "parts": [["text": initialUserMessage]]]
        ]
        return try await send(maxTokens: maxTokens)
    }

    func continueConversation(toolResults: [AIToolResult], maxTokens: Int) async throws -> AIProviderResponse {
        // Gemini: 모든 툴 결과를 하나의 user 메시지의 parts 배열에 functionResponse로 추가
        var parts: [[String: Any]] = []
        for r in toolResults {
            let responseContent: Any
            if let data = r.content.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                responseContent = parsed
            } else {
                responseContent = ["content": r.content]
            }
            parts.append([
                "functionResponse": [
                    "name": extractFunctionName(forId: r.id) ?? "unknown",
                    "response": ["content": responseContent]
                ]
            ])
        }
        contents.append(["role": "user", "parts": parts])
        return try await send(maxTokens: maxTokens)
    }

    // Gemini는 tool_use_id 개념이 없어서 name으로 match. 직전 assistant의 functionCall name을 id와 연결해둠.
    private var pendingCallNames: [String: String] = [:] // toolUseId -> name

    private func extractFunctionName(forId id: String) -> String? {
        pendingCallNames[id]
    }

    private func send(maxTokens: Int) async throws -> AIProviderResponse {
        let key = try loadKey()
        var body: [String: Any] = [
            "contents": contents,
            "systemInstruction": systemInstruction,
            "generationConfig": ["maxOutputTokens": maxTokens],
        ]
        if !tools.isEmpty { body["tools"] = tools }

        var request = URLRequest(url: endpointURL(key: key))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse("non-HTTP") }
        guard (200..<300).contains(http.statusCode) else {
            throw AIProviderError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.decodingFailed("not json")
        }
        guard let candidates = obj["candidates"] as? [[String: Any]], let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AIProviderError.decodingFailed("no candidates: \(text.prefix(500))")
        }

        let stopReason = (first["finishReason"] as? String) ?? ""

        var textParts: [String] = []
        var toolUses: [AIToolUse] = []
        for part in parts {
            if let t = part["text"] as? String {
                textParts.append(t)
            }
            if let fc = part["functionCall"] as? [String: Any],
               let name = fc["name"] as? String {
                let args = (fc["args"] as? [String: Any]) ?? [:]
                // Gemini는 툴콜 id를 주지 않으므로 우리가 부여
                let id = "gemini-call-\(UUID().uuidString)"
                pendingCallNames[id] = name
                toolUses.append(AIToolUse(id: id, name: name, input: args))
            }
        }

        // assistant (model) turn 누적 — raw 그대로
        contents.append(["role": "model", "parts": parts])

        if let usage = obj["usageMetadata"] as? [String: Any] {
            inputTokensUsed += (usage["promptTokenCount"] as? Int) ?? 0
            outputTokensUsed += (usage["candidatesTokenCount"] as? Int) ?? 0
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

    /// JSON Schema → Gemini OpenAPI subset 변환 (type 값을 대문자로).
    private static func convertSchemaForGemini(_ schema: [String: Any]) -> [String: Any] {
        var out = schema
        if let t = out["type"] as? String {
            out["type"] = t.uppercased()
        }
        if var props = out["properties"] as? [String: Any] {
            for (k, v) in props {
                if let child = v as? [String: Any] {
                    props[k] = convertSchemaForGemini(child)
                }
            }
            out["properties"] = props
        }
        if let items = out["items"] as? [String: Any] {
            out["items"] = convertSchemaForGemini(items)
        }
        return out
    }
}
