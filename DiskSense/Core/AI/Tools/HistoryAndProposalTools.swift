import Foundation

// MARK: - get_cleanup_history

struct GetCleanupHistoryTool: AgentTool {
    let name = "get_cleanup_history"
    let description = "과거 정리 기록을 반환합니다 (날짜, 대상 경로, 이유, 유저 승인 여부). 유저의 선호 패턴을 파악하세요."
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "limit": ["type": "integer", "description": "최근 N개 (기본 20)"]
            ]
        ]
    }

    func execute(input: [String: Any], context: AgentContext) async throws -> Any {
        let limit = (input["limit"] as? Int) ?? 20
        let history = context.historyProvider()
        let recent = history.prefix(limit)
        let df = ISO8601DateFormatter()
        return [
            "count": recent.count,
            "items": recent.map { (h: HistorySnapshot) -> [String: Any] in
                [
                    "executed_at": df.string(from: h.executedAt),
                    "bytes_freed": h.totalSizeFreed,
                    "item_count": h.itemCount,
                    "paths": h.suggestions.flatMap { $0.targetPaths },
                    "reasons": h.suggestions.map { $0.reason },
                ]
            }
        ]
    }
}

// MARK: - propose_cleanup

struct ProposeCleanupTool: AgentTool {
    let name = "propose_cleanup"
    let description = """
    정리 제안을 누적 리스트에 추가합니다. 각 제안엔 반드시 증거(조사한 툴 호출 결과)를 reason에 포함하세요.
    risk: 'safe'(재생성 가능/명확히 불필요) | 'caution'(검토 권장) | 'danger'(매우 신중). danger는 제안하지 마세요.
    """
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "paths": ["type": "array", "items": ["type": "string"], "description": "삭제 대상 경로들 (홈 하위)"],
                "estimated_bytes": ["type": "integer"],
                "reason": ["type": "string", "description": "왜 정리해도 되는지 구체적 증거 포함 (날짜/크기/툴 결과 인용)"],
                "risk": ["type": "string", "enum": ["safe", "caution"]],
                "recoverable": ["type": "boolean"],
            ],
            "required": ["paths", "estimated_bytes", "reason", "risk", "recoverable"]
        ]
    }

    func execute(input: [String: Any], context: AgentContext) async throws -> Any {
        guard let paths = input["paths"] as? [String],
              let reason = input["reason"] as? String,
              let riskStr = input["risk"] as? String,
              let recoverable = input["recoverable"] as? Bool
        else { throw AgentToolError.invalidArgument("paths/reason/risk/recoverable 필요") }

        // 모든 경로 PathGuard 검증
        var validated: [String] = []
        for p in paths {
            do { validated.append(try PathGuard.validate(p)) }
            catch { throw AgentToolError.accessDenied("\(p): \(error)") }
        }

        let risk: RiskLevel = RiskLevel(rawValue: riskStr) ?? .caution
        let estimatedBytes: Int64
        if let n = input["estimated_bytes"] as? Int64 { estimatedBytes = n }
        else if let n = input["estimated_bytes"] as? Int { estimatedBytes = Int64(n) }
        else if let n = input["estimated_bytes"] as? Double { estimatedBytes = Int64(n) }
        else { estimatedBytes = 0 }

        let suggestion = AISuggestion(
            targetPaths: validated,
            estimatedBytes: estimatedBytes,
            reason: reason,
            risk: risk,
            recoverable: recoverable
        )
        context.proposals.append(suggestion)
        context.eventEmitter(.proposal(suggestion: suggestion))

        return ["ok": true, "proposal_count": context.proposals.count]
    }
}

// MARK: - finish

struct FinishTool: AgentTool {
    let name = "finish"
    let description = "모든 조사와 제안이 끝났을 때 호출합니다. 분석 전체에 대한 한 줄 요약을 전달하세요."
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "summary": ["type": "string", "description": "한 줄 요약 (몇 개 제안, 총 얼마 절약 가능 등)"]
            ],
            "required": ["summary"]
        ]
    }

    func execute(input: [String: Any], context: AgentContext) async throws -> Any {
        let summary = (input["summary"] as? String) ?? ""
        context.finished = true
        context.finalSummary = summary
        context.eventEmitter(.finished(summary: summary))
        return ["ok": true]
    }
}

// MARK: - Registry

enum ToolRegistry {
    static let all: [AgentTool] = [
        ListDirectoryTool(),
        GetItemDetailsTool(),
        SampleFileNamesTool(),
        CheckDevProjectTool(),
        GetLastOpenedTool(),
        CountFilesByExtensionTool(),
        SearchByPatternTool(),
        GetCleanupHistoryTool(),
        ProposeCleanupTool(),
        FinishTool(),
    ]

    static func find(_ name: String) -> AgentTool? {
        all.first { $0.name == name }
    }

    /// Anthropic API의 tools 배열 포맷으로 변환
    static func toAnthropicTools() -> [[String: Any]] {
        all.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema
            ]
        }
    }
}
