import Foundation

protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    /// JSON Schema 형식 input 정의 (Anthropic tool use 규격).
    var inputSchema: [String: Any] { get }
    func execute(input: [String: Any], context: AgentContext) async throws -> Any
}

enum AgentToolError: Error, LocalizedError {
    case invalidArgument(String)
    case accessDenied(String)
    case notFound(String)
    case outsideHome(String)
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let m): return "invalid_argument: \(m)"
        case .accessDenied(let m):    return "access_denied: \(m)"
        case .notFound(let m):        return "not_found: \(m)"
        case .outsideHome(let m):     return "outside_home: \(m)"
        case .internalError(let m):   return "internal_error: \(m)"
        }
    }
}

/// 히스토리 Sendable DTO.
struct HistorySnapshot: Sendable {
    let executedAt: Date
    let totalSizeFreed: Int64
    let itemCount: Int
    let suggestions: [AISuggestion]
}

/// 에이전트 runtime 공유 상태.
final class AgentContext {
    var proposals: [AISuggestion] = []
    var finished: Bool = false
    var finalSummary: String = ""
    let historyProvider: @Sendable () -> [HistorySnapshot]
    let eventEmitter: @Sendable (AgentEvent) -> Void

    init(
        historyProvider: @escaping @Sendable () -> [HistorySnapshot],
        eventEmitter: @escaping @Sendable (AgentEvent) -> Void
    ) {
        self.historyProvider = historyProvider
        self.eventEmitter = eventEmitter
    }
}

/// 경로가 home 하위이고 ProtectedPaths가 아님을 검증.
enum PathGuard {
    static func validate(_ path: String) throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let home = NSHomeDirectory()
        let resolved = URL(fileURLWithPath: expanded).standardizedFileURL.path
        if !resolved.hasPrefix(home) {
            throw AgentToolError.outsideHome(resolved)
        }
        if ProtectedPaths.isProtected(resolved) {
            throw AgentToolError.accessDenied(resolved)
        }
        return resolved
    }
}
