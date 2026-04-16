import Foundation
import SwiftData

/// 볼륨 사용량 스냅샷. 주기적 폴링(periodic)과 스캔 완료(scan) 두 종류.
@Model
final class StorageSnapshot {
    @Attribute(.unique) var id: UUID
    var recordedAt: Date
    var totalCapacity: Int64
    var totalUsed: Int64
    var usagePercent: Double

    /// "periodic" = 백그라운드 VolumeInfo 폴링, "scan" = 디스크 스캔 완료 시점
    var kind: String

    // scan 타입일 때만 채워지는 메타데이터
    var scanItemCount: Int?
    var scanDuration: Double?
    var scanTopCategories: String?   // "developer:12.3GB,cache:8.1GB,..." 경량 직렬화

    init(id: UUID = UUID(),
         recordedAt: Date = Date(),
         totalCapacity: Int64,
         totalUsed: Int64,
         kind: String = "periodic",
         scanItemCount: Int? = nil,
         scanDuration: Double? = nil,
         scanTopCategories: String? = nil) {
        self.id = id
        self.recordedAt = recordedAt
        self.totalCapacity = totalCapacity
        self.totalUsed = totalUsed
        self.usagePercent = totalCapacity > 0
            ? Double(totalUsed) / Double(totalCapacity) * 100.0
            : 0
        self.kind = kind
        self.scanItemCount = scanItemCount
        self.scanDuration = scanDuration
        self.scanTopCategories = scanTopCategories
    }

    var isScan: Bool { kind == "scan" }
}
