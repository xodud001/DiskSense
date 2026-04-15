import Foundation

enum SuggestionParser {
    private struct Envelope: Decodable {
        let suggestions: [Raw]
    }
    private struct Raw: Decodable {
        let path: String
        let size_bytes: Int64?
        let reason: String
        let risk: String
        let action: String?
        let recoverable: Bool?
        let category: String?
        let priority: Int?
    }

    static func parse(_ jsonText: String) -> [AISuggestion] {
        guard let data = extractJSON(from: jsonText)?.data(using: .utf8) else { return [] }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return [] }
        return env.suggestions.map { raw in
            AISuggestion(
                targetPaths: [raw.path],
                estimatedBytes: raw.size_bytes ?? 0,
                reason: raw.reason,
                risk: RiskLevel(rawValue: raw.risk) ?? .caution,
                recoverable: raw.recoverable ?? true
            )
        }
    }

    /// Claude가 code fence로 감싸거나 앞뒤 설명을 넣어도 JSON만 뽑아낸다.
    private static func extractJSON(from text: String) -> String? {
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return nil
    }
}
