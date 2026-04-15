import Foundation

struct AISuggestion: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var targetPaths: [String]
    var estimatedBytes: Int64
    var reason: String
    var risk: RiskLevel
    var recoverable: Bool
    var isApproved: Bool = false
}
