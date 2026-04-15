import Foundation

/// 에이전트 루프가 UI로 emit하는 이벤트.
enum AgentEvent: Identifiable, Sendable {
    case thinking(id: UUID = UUID(), text: String)
    case toolCall(id: UUID = UUID(), name: String, args: String)
    case toolResult(id: UUID = UUID(), name: String, summary: String, isError: Bool)
    case proposal(id: UUID = UUID(), suggestion: AISuggestion)
    case finished(id: UUID = UUID(), summary: String)
    case error(id: UUID = UUID(), message: String)

    var id: UUID {
        switch self {
        case .thinking(let id, _): return id
        case .toolCall(let id, _, _): return id
        case .toolResult(let id, _, _, _): return id
        case .proposal(let id, _): return id
        case .finished(let id, _): return id
        case .error(let id, _): return id
        }
    }
}
