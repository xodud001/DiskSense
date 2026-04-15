import Foundation

/// 스캔 결과를 Application Support에 JSON으로 영속화한다.
/// Phase B (FSEvents 기반 증분 스캔)에서는 여기에 per-directory mtime을 덧붙일 예정.
enum ScanCache {
    private static let fileName = "last_scan.json"

    private static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("DiskSense", isDirectory: true)
    }

    private static var fileURL: URL {
        supportDir.appendingPathComponent(fileName)
    }

    static func save(_ result: ScanResult) {
        do {
            try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(result)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[ScanCache] save failed: \(error)")
        }
    }

    static func load() -> ScanResult? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ScanResult.self, from: data)
    }

    /// 캐시가 `ttlHours`보다 오래되었으면 true.
    static func isStale(ttlHours: Double = 12) -> Bool {
        guard let result = load() else { return true }
        return Date().timeIntervalSince(result.scannedAt) > ttlHours * 3600
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// StorageCategory를 키로 한 [StorageCategory: Int64]는 JSONEncoder가 기본 Dictionary로
/// 인코딩 가능 (RawRepresentable key). 별도 작업 불필요.
