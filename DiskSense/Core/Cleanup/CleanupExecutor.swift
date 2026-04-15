import Foundation

struct CleanupResult {
    var succeededPaths: [String] = []
    var failures: [(String, Error)] = []
    var totalBytesFreed: Int64 = 0
}

enum CleanupMode { case trash, permanent }

enum CleanupExecutor {
    /// 여러 AISuggestion을 안전 장치 거쳐 실행.
    static func execute(
        suggestions: [AISuggestion],
        mode: CleanupMode,
        progress: @Sendable @escaping (Int, Int, String) -> Void = { _, _, _ in }
    ) async -> CleanupResult {
        var result = CleanupResult()
        let approved = suggestions.filter { $0.isApproved }
        let allPaths = approved.flatMap { $0.targetPaths }
        let (_, rejected) = SafetyGuard.filterValid(paths: allPaths)
        let rejectedSet = Set(rejected.map { $0.0 })

        var processed = 0
        let total = allPaths.count - rejectedSet.count

        for suggestion in approved {
            for path in suggestion.targetPaths {
                if rejectedSet.contains(path) {
                    result.failures.append((path, SafetyViolation.protectedPath(path)))
                    continue
                }
                processed += 1
                progress(processed, total, path)

                let size = (try? byteSize(at: path)) ?? suggestion.estimatedBytes
                do {
                    switch mode {
                    case .trash:     try await moveToTrash(path: path)
                    case .permanent: try await permanentDelete(path: path)
                    }
                    result.succeededPaths.append(path)
                    result.totalBytesFreed += size
                } catch {
                    result.failures.append((path, error))
                }
            }
        }
        return result
    }

    private static func moveToTrash(path: String) async throws {
        let url = URL(fileURLWithPath: path)
        // FileManager.trashItem은 synchronous에 main thread-safe.
        var resultURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultURL)
    }

    private static func permanentDelete(path: String) async throws {
        try FileManager.default.removeItem(atPath: path)
    }

    private static func byteSize(at path: String) throws -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey]
        let values = try url.resourceValues(forKeys: Set(keys))
        if values.isDirectory == true {
            var total: Int64 = 0
            if let e = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: keys, options: []
            ) {
                while let next = e.nextObject() {
                    guard let u = next as? URL,
                          let v = try? u.resourceValues(forKeys: Set(keys)) else { continue }
                    total += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
                }
            }
            return total
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }
}
