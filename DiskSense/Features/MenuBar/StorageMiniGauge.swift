import SwiftUI

/// 카테고리 색상 세그먼트로 구성된 수평 프로그레스 바.
/// 볼륨 기준: used/capacity가 전체 채움 비율, 그 안을 카테고리별 비중으로 분할.
struct StorageMiniGauge: View {
    let used: Int64
    let capacity: Int64
    let breakdown: [StorageCategory: Int64]

    private var usedRatio: Double {
        guard capacity > 0 else { return 0 }
        return min(1.0, Double(used) / Double(capacity))
    }
    private var scannedTotal: Int64 { breakdown.values.reduce(0, +) }

    private struct Seg {
        let width: Double
        let color: Color
    }

    private func segments() -> [Seg] {
        guard used > 0, usedRatio > 0 else { return [] }
        var out: [Seg] = []
        let scannedFrac = min(1.0, Double(scannedTotal) / Double(used))
        for cat in StorageCategory.allCases {
            guard let bytes = breakdown[cat], bytes > 0 else { continue }
            let share = Double(bytes) / Double(used) * usedRatio
            out.append(Seg(width: share, color: cat.color))
        }
        let unexplainedFrac = max(0, 1.0 - scannedFrac) * usedRatio
        if unexplainedFrac > 0 {
            out.append(Seg(width: unexplainedFrac, color: Color(nsColor: .tertiaryLabelColor)))
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12))
                HStack(spacing: 0) {
                    ForEach(Array(segments().enumerated()), id: \.offset) { _, seg in
                        Rectangle()
                            .fill(seg.color)
                            .frame(width: max(0, total * seg.width))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(height: 8)
    }
}
