import Foundation
import SwiftData

@Model
final class CleanupHistory {
    @Attribute(.unique) var id: UUID
    var executedAt: Date
    var totalSizeFreed: Int64
    var itemCount: Int
    var suggestionsJSON: Data
    var snapshotPath: String?

    init(id: UUID = UUID(),
         executedAt: Date,
         totalSizeFreed: Int64,
         itemCount: Int,
         suggestions: [AISuggestion],
         snapshotPath: String? = nil) {
        self.id = id
        self.executedAt = executedAt
        self.totalSizeFreed = totalSizeFreed
        self.itemCount = itemCount
        self.suggestionsJSON = (try? JSONEncoder().encode(suggestions)) ?? Data()
        self.snapshotPath = snapshotPath
    }

    var suggestions: [AISuggestion] {
        (try? JSONDecoder().decode([AISuggestion].self, from: suggestionsJSON)) ?? []
    }
}
