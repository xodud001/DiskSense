import SwiftUI

/// 카테고리 세그먼트 프로그레스 바 (Capsule 양끝 둥근 형태)
/// 숫자 표기는 상위 뷰가 담당. 이 컴포넌트는 바 + 범례만.
struct StorageGaugeView: View {
    let used: Int64
    let capacity: Int64
    let breakdown: [StorageCategory: Int64]
    @Binding var hoveredLabel: String?

    private var scannedTotal: Int64 { breakdown.values.reduce(0, +) }

    struct Segment: Identifiable {
        let id = UUID()
        let color: Color
        let label: String
        let bytes: Int64
        let fractionOfTotal: Double
    }

    var segments: [Segment] {
        Self.computeSegments(used: used, capacity: capacity, breakdown: breakdown)
    }

    static func computeSegments(used: Int64, capacity: Int64, breakdown: [StorageCategory: Int64]) -> [Segment] {
        guard capacity > 0 else { return [] }
        var out: [Segment] = []
        for cat in StorageCategory.allCases {
            guard let bytes = breakdown[cat], bytes > 0 else { continue }
            out.append(Segment(
                color: cat.color, label: cat.displayName, bytes: bytes,
                fractionOfTotal: Double(bytes) / Double(capacity)
            ))
        }
        let scannedTotal = breakdown.values.reduce(0, +)
        let unexplained = max(0, used - scannedTotal)
        if unexplained > 0 {
            out.append(Segment(
                color: Color(red: 0.42, green: 0.32, blue: 0.52),
                label: "시스템/스냅샷 (미분석)", bytes: unexplained,
                fractionOfTotal: Double(unexplained) / Double(capacity)
            ))
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.14))
                HStack(spacing: 0) {
                    ForEach(segments) { seg in
                        Rectangle()
                            .fill(seg.color)
                            .frame(width: max(0, total * seg.fractionOfTotal))
                            .opacity(opacityFor(seg))
                            .onHover { inside in
                                if inside { hoveredLabel = seg.label }
                                else if hoveredLabel == seg.label { hoveredLabel = nil }
                            }
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 14)
        .animation(.easeInOut(duration: 0.15), value: hoveredLabel)
    }

    private func opacityFor(_ seg: Segment) -> Double {
        guard let hoveredLabel else { return 1.0 }
        return seg.label == hoveredLabel ? 1.0 : 0.35
    }
}

/// 카테고리 범례 칩 (색 점 + 이름 + 용량).
struct SegmentLegend: View {
    let segments: [StorageGaugeView.Segment]
    let availableBytes: Int64
    @Binding var hoveredLabel: String?

    var body: some View {
        WrapHStack(spacing: 8, lineSpacing: 8) {
            ForEach(segments) { seg in
                chip(color: seg.color, label: seg.label, bytes: seg.bytes, active: hoveredLabel == seg.label)
                    .onHover { inside in
                        if inside { hoveredLabel = seg.label }
                        else if hoveredLabel == seg.label { hoveredLabel = nil }
                    }
            }
            if availableBytes > 0 {
                chip(color: .green, label: "여유", bytes: availableBytes, active: false, isAvailable: true)
            }
        }
    }

    @ViewBuilder
    private func chip(color: Color, label: String, bytes: Int64, active: Bool, isAvailable: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption.weight(.medium))
                .foregroundStyle(active ? .primary : .secondary)
            Text(ByteFormatter.string(bytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(isAvailable ? .green : (active ? color : .secondary))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(active ? color.opacity(0.14) : Color.secondary.opacity(0.08))
        }
        .animation(.easeInOut(duration: 0.12), value: active)
    }
}

/// 가변 너비에서 자동 줄바꿈되는 HStack (chip용).
struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        // iOS 16+ / macOS 13+ Layout 사용 없이 간단 구현: HStack이지만 줄바꿈 지원 위해 ViewThatFits + ForEach 어려움 —
        // 가장 간단한 구현으로 HStack wrap 은 nested VStack of HStacks 필요. 여기선 flat FlowLayout.
        FlowLayout(spacing: spacing, lineSpacing: lineSpacing) { content() }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var height: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if lineWidth + s.width > maxWidth && lineWidth > 0 {
                width = max(width, lineWidth - spacing)
                height += lineHeight + lineSpacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
        width = max(width, lineWidth - spacing)
        height += lineHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}
