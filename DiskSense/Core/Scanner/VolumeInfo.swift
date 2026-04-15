import Foundation

/// 볼륨의 실제 사용량 — Finder/디스크 유틸리티와 동일한 방식.
/// URLResourceKey로 OS에게 직접 질의. APFS 스냅샷/퍼지 가능 공간까지 반영된 값.
enum VolumeInfo {
    struct Usage {
        let total: Int64
        let used: Int64          // total - available
        let available: Int64     // 현재 즉시 사용 가능 (퍼지 가능 포함)
        let availableImportant: Int64 // macOS가 '중요' 용도로 안전하게 쓸 수 있는 양
    }

    /// 시작 볼륨 기준 사용량.
    static func startupVolume() -> Usage? {
        usage(for: URL(fileURLWithPath: NSHomeDirectory()))
    }

    static func usage(for url: URL) -> Usage? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity
        else { return nil }
        let importantAvail = Int64(values.volumeAvailableCapacityForImportantUsage ?? Int64(available))
        return Usage(
            total: Int64(total),
            used: Int64(total) - Int64(available),
            available: Int64(available),
            availableImportant: importantAvail
        )
    }
}
