import Foundation

/// API 키가 없거나 네트워크가 오프라인일 때 룰 기반 제안.
enum OfflineFallback {
    static func suggest(items: [DiskItem]) -> [AISuggestion] {
        items.compactMap { item -> AISuggestion? in
            let ageInDays = Int(Date().timeIntervalSince(item.modifiedDate) / 86400)
            let gb = Double(item.sizeBytes) / 1_073_741_824.0

            if item.category == .developer && gb >= 0.5 {
                return AISuggestion(
                    targetPaths: [item.path],
                    estimatedBytes: item.sizeBytes,
                    reason: "개발 캐시/빌드 아티팩트. 재빌드 시 자동 재생성됨 (\(ageInDays)일 전 마지막 수정).",
                    risk: .safe,
                    recoverable: true
                )
            }
            if item.category == .cache && gb >= 0.2 {
                return AISuggestion(
                    targetPaths: [item.path],
                    estimatedBytes: item.sizeBytes,
                    reason: "캐시 데이터. 필요 시 재생성됨 (\(ageInDays)일 전 마지막 수정).",
                    risk: .safe,
                    recoverable: true
                )
            }
            if ageInDays > 180 && gb >= 1.0 && (item.category == .documents || item.category == .other) {
                return AISuggestion(
                    targetPaths: [item.path],
                    estimatedBytes: item.sizeBytes,
                    reason: "\(ageInDays)일 이상 수정되지 않은 대용량 항목. 검토 후 정리 권장.",
                    risk: .caution,
                    recoverable: true
                )
            }
            return nil
        }
        .sorted { $0.estimatedBytes > $1.estimatedBytes }
        .prefix(30)
        .map { $0 }
    }
}
