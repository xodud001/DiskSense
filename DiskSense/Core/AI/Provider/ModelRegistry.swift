import Foundation

enum ModelRegistry {
    static let models: [AIModel] = [
        // Anthropic
        AIModel(id: "claude-opus-4-6", displayName: "Claude Opus 4.6", provider: .anthropic,
                supportsTools: true, inputCostPerMTok: 15, outputCostPerMTok: 75),
        AIModel(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6", provider: .anthropic,
                supportsTools: true, inputCostPerMTok: 3, outputCostPerMTok: 15),
        AIModel(id: "claude-opus-4-5", displayName: "Claude Opus 4.5", provider: .anthropic,
                supportsTools: true, inputCostPerMTok: 15, outputCostPerMTok: 75),
        AIModel(id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5", provider: .anthropic,
                supportsTools: true, inputCostPerMTok: 3, outputCostPerMTok: 15),
        AIModel(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5", provider: .anthropic,
                supportsTools: true, inputCostPerMTok: 1, outputCostPerMTok: 5),

        // OpenAI
        AIModel(id: "gpt-5", displayName: "GPT-5", provider: .openai,
                supportsTools: true, inputCostPerMTok: 1.25, outputCostPerMTok: 10),
        AIModel(id: "gpt-5-mini", displayName: "GPT-5 Mini", provider: .openai,
                supportsTools: true, inputCostPerMTok: 0.25, outputCostPerMTok: 2),
        AIModel(id: "gpt-4.1", displayName: "GPT-4.1", provider: .openai,
                supportsTools: true, inputCostPerMTok: 2, outputCostPerMTok: 8),

        // Google
        AIModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro", provider: .google,
                supportsTools: true, inputCostPerMTok: 1.25, outputCostPerMTok: 10),
        AIModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", provider: .google,
                supportsTools: true, inputCostPerMTok: 0.15, outputCostPerMTok: 0.6),
    ]

    static let `default`: AIModel = models.first { $0.id == "claude-sonnet-4-6" } ?? models[0]

    static func find(_ id: String) -> AIModel? { models.first { $0.id == id } }

    static func models(for provider: AIProvider) -> [AIModel] {
        models.filter { $0.provider == provider }
    }

    /// 첫 실행 시 — 등록된 키 중 가장 저렴한 모델 기본 선택. 여러 있으면 default.
    static func firstRunDefault() -> AIModel {
        let hasAnthropic = KeychainHelper.has(key: AIProvider.anthropic.keychainKey)
        let hasOpenAI    = KeychainHelper.has(key: AIProvider.openai.keychainKey)
        let hasGoogle    = KeychainHelper.has(key: AIProvider.google.keychainKey)

        if hasAnthropic { return find("claude-sonnet-4-6")! }
        if hasOpenAI    { return find("gpt-5-mini")! }
        if hasGoogle    { return find("gemini-2.5-flash")! }
        return `default`
    }
}

enum ProviderFactory {
    static func make(modelId: String) throws -> AIProviderClient {
        guard let model = ModelRegistry.find(modelId) else {
            throw AIProviderError.modelNotFound(modelId)
        }
        switch model.provider {
        case .anthropic: return AnthropicClient(modelId: modelId)
        case .openai:    return OpenAIClient(modelId: modelId)
        case .google:    return GoogleClient(modelId: modelId)
        }
    }
}
