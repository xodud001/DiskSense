import Foundation

/// 실행 전 JSON 스냅샷을 Application Support에 저장.
enum SnapshotManager {
    struct Snapshot: Codable {
        let id: UUID
        let createdAt: Date
        let suggestions: [AISuggestion]
    }

    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("DiskSense/Snapshots", isDirectory: true)
    }

    @discardableResult
    static func write(suggestions: [AISuggestion]) -> String? {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let snap = Snapshot(id: UUID(), createdAt: .now, suggestions: suggestions)
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(snap)
            let url = dir.appendingPathComponent("\(snap.id.uuidString).json")
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            print("[SnapshotManager] write failed: \(error)")
            return nil
        }
    }
}
