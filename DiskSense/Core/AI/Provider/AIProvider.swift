import Foundation

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case anthropic = "anthropic"
    case openai    = "openai"
    case google    = "google"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai:    return "OpenAI"
        case .google:    return "Google (Gemini)"
        }
    }

    var keychainKey: String { "\(rawValue)-api-key" }

    var apiKeyHelpURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai:    return URL(string: "https://platform.openai.com/api-keys")!
        case .google:    return URL(string: "https://aistudio.google.com/apikey")!
        }
    }

    var keyPrefix: String {
        switch self {
        case .anthropic: return "sk-ant-"
        case .openai:    return "sk-"
        case .google:    return ""
        }
    }

    var accentColor: String {
        switch self {
        case .anthropic: return "orange"
        case .openai:    return "green"
        case .google:    return "blue"
        }
    }
}

struct AIModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let provider: AIProvider
    let supportsTools: Bool
    let inputCostPerMTok: Double
    let outputCostPerMTok: Double
}

struct AIToolUse: Sendable {
    let id: String
    let name: String
    let input: [String: Any]

    // Equatable/Hashable를 위해 id만 기준
    static func == (lhs: AIToolUse, rhs: AIToolUse) -> Bool { lhs.id == rhs.id }
}

struct AIToolResult: Sendable {
    let id: String       // tool_use id
    let content: String  // JSON 문자열
    let isError: Bool
}

struct AITool: Sendable {
    let name: String
    let description: String
    let inputSchema: [String: Any]  // JSON Schema
}

struct AIProviderResponse: Sendable {
    let text: String
    let toolUses: [AIToolUse]
    let stopReason: String
    let inputTokens: Int
    let outputTokens: Int
}

enum AIProviderError: Error, LocalizedError {
    case missingKey(AIProvider)
    case invalidResponse(String)
    case httpError(Int, String)
    case decodingFailed(String)
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let p): return "\(p.displayName) API 키가 설정되지 않았습니다. 설정 탭에서 입력하세요."
        case .invalidResponse(let m): return "유효하지 않은 응답: \(m)"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .decodingFailed(let m): return "응답 파싱 실패: \(m)"
        case .modelNotFound(let id): return "모델을 찾을 수 없습니다: \(id)"
        }
    }
}

/// 프로바이더 클라이언트. 한 run 단위로 생성해서 사용. 대화 히스토리를 내부에 보관.
protocol AIProviderClient: AnyObject {
    var provider: AIProvider { get }
    var modelId: String { get }
    var inputTokensUsed: Int { get }
    var outputTokensUsed: Int { get }

    /// 첫 호출 — 시스템 프롬프트 + 초기 유저 메시지 + 툴로 모델 호출.
    func start(
        systemPrompt: String,
        initialUserMessage: String,
        tools: [AITool],
        maxTokens: Int
    ) async throws -> AIProviderResponse

    /// 이전 턴에 받은 tool_use들에 대한 결과를 돌려주고 다음 턴을 받아옴.
    func continueConversation(
        toolResults: [AIToolResult],
        maxTokens: Int
    ) async throws -> AIProviderResponse
}
