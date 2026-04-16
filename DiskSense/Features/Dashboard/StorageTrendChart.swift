import SwiftUI
import SwiftData
import Charts

struct StorageTrendChart: View {
    @Query(sort: \StorageSnapshot.recordedAt, order: .forward) private var allSnapshots: [StorageSnapshot]
    @State private var selectedRange: TrendRange = .day
    @State private var hoveredScan: StorageSnapshot?
    @State private var hoverLocation: CGPoint = .zero

    enum TrendRange: String, CaseIterable {
        case day = "24시간"
        case week = "7일"
        case month = "30일"
        case all = "전체"
    }

    private var filtered: [StorageSnapshot] {
        let cutoff: Date?
        switch selectedRange {
        case .day:   cutoff = Calendar.current.date(byAdding: .hour, value: -24, to: Date())
        case .week:  cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .month: cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        case .all:   cutoff = nil
        }
        if let cutoff {
            return allSnapshots.filter { $0.recordedAt >= cutoff }
        }
        return allSnapshots
    }

    private var periodicPoints: [StorageSnapshot] {
        filtered.filter { !$0.isScan }
    }

    private var scanPoints: [StorageSnapshot] {
        filtered.filter { $0.isScan }
    }

    private var yDomain: ClosedRange<Double> {
        guard !filtered.isEmpty else { return 0...100 }
        let values = filtered.map(\.usagePercent)
        let lo = max(0, (values.min() ?? 0) - 3)
        let hi = min(100, (values.max() ?? 100) + 3)
        return lo...hi
    }

    private var delta: Double? {
        guard filtered.count >= 2,
              let first = filtered.first,
              let last = filtered.last else { return nil }
        return last.usagePercent - first.usagePercent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if filtered.count < 2 {
                emptyState
            } else {
                chartContent
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("저장공간 추이")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            if let delta {
                deltaLabel(delta)
            }
            if !scanPoints.isEmpty {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.orange.opacity(0.6))
                        .frame(width: 12, height: 2)
                    Text("스캔").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.leading, 8)
            }
            Spacer()
            Picker("기간", selection: $selectedRange) {
                ForEach(TrendRange.allCases, id: \.self) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2).foregroundStyle(.tertiary)
                Text("데이터가 쌓이면 추이를 확인할 수 있어요")
                    .font(.caption).foregroundStyle(.secondary)
                Text("3분마다 자동으로 기록됩니다")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(height: 140)
    }

    // MARK: - Chart

    private var chartContent: some View {
        ZStack(alignment: .topLeading) {
            Chart {
                // 연속 사용률 라인 (periodic + scan 모두 포함)
                ForEach(filtered) { snap in
                    LineMark(
                        x: .value("시간", snap.recordedAt),
                        y: .value("사용률", snap.usagePercent)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(trendGradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }

                // 스캔 시점 수직선
                ForEach(scanPoints) { scan in
                    RuleMark(x: .value("스캔", scan.recordedAt))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(.orange.opacity(0.6))
                        .annotation(position: .top, spacing: 4) {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                }

                // 스캔 포인트 강조
                ForEach(scanPoints) { scan in
                    PointMark(
                        x: .value("시간", scan.recordedAt),
                        y: .value("사용률", scan.usagePercent)
                    )
                    .symbolSize(40)
                    .foregroundStyle(.orange)
                }
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))%").font(.caption2).monospacedDigit()
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(xAxisLabel(for: d)).font(.caption2)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoverLocation = location
                                hoveredScan = findNearestScan(at: location, proxy: proxy, geo: geo)
                            case .ended:
                                hoveredScan = nil
                            }
                        }
                }
            }
            .frame(height: 180)

            // Hover 팝오버
            if let scan = hoveredScan {
                scanPopover(for: scan)
                    .offset(x: max(0, min(hoverLocation.x - 100, 400)), y: 0)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: hoveredScan?.id)
            }
        }
    }

    // MARK: - Scan Popover

    private func scanPopover(for scan: StorageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("스캔 결과")
                    .font(.caption.weight(.semibold))
            }
            Divider()
            HStack(spacing: 12) {
                statItem("사용률", String(format: "%.1f%%", scan.usagePercent))
                statItem("사용량", formatBytes(scan.totalUsed))
                if let count = scan.scanItemCount {
                    statItem("항목 수", "\(count.formatted())개")
                }
                if let dur = scan.scanDuration {
                    statItem("소요", String(format: "%.1fs", dur))
                }
            }
            if let cats = scan.scanTopCategories, !cats.isEmpty {
                Divider()
                Text("상위 카테고리").font(.caption2).foregroundStyle(.secondary)
                ForEach(parseCategoryEntries(cats), id: \.0) { name, size in
                    HStack(spacing: 4) {
                        Circle().fill(categoryColor(name)).frame(width: 6, height: 6)
                        Text(categoryDisplayName(name))
                            .font(.caption2)
                        Spacer()
                        Text(size).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            Text(scan.recordedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(width: 200)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
    }

    // MARK: - Helpers

    private func findNearestScan(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> StorageSnapshot? {
        let plotFrame = geo[proxy.plotFrame!]
        let relX = location.x - plotFrame.origin.x
        guard let date: Date = proxy.value(atX: relX) else { return nil }
        // 가장 가까운 스캔 포인트 (30분 반경 이내)
        let threshold: TimeInterval = 1800
        return scanPoints.min(by: {
            abs($0.recordedAt.timeIntervalSince(date)) < abs($1.recordedAt.timeIntervalSince(date))
        }).flatMap {
            abs($0.recordedAt.timeIntervalSince(date)) < threshold ? $0 : nil
        }
    }

    private func xAxisLabel(for date: Date) -> String {
        switch selectedRange {
        case .day:
            return date.formatted(.dateTime.hour().minute())
        case .week, .month, .all:
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.medium)).monospacedDigit()
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteFormatter.string(bytes)
    }

    private func parseCategoryEntries(_ raw: String) -> [(String, String)] {
        raw.split(separator: ",").compactMap { entry in
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        }
    }

    private func categoryDisplayName(_ raw: String) -> String {
        switch raw {
        case "developer": return "개발 환경"
        case "cache":     return "캐시"
        case "apps":      return "앱"
        case "documents":  return "문서"
        case "photos":    return "사진"
        case "system":    return "시스템"
        case "mail":      return "메일"
        case "trash":     return "휴지통"
        case "other":     return "기타"
        default:          return raw
        }
    }

    private func categoryColor(_ raw: String) -> Color {
        switch raw {
        case "developer": return .purple
        case "cache":     return .orange
        case "apps":      return .blue
        case "documents":  return .cyan
        case "photos":    return .green
        case "system":    return .gray
        case "mail":      return .red
        case "trash":     return .brown
        default:          return .secondary
        }
    }

    private var trendGradient: LinearGradient {
        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
    }

    private var areaGradient: LinearGradient {
        LinearGradient(colors: [.blue.opacity(0.15), .purple.opacity(0.05)], startPoint: .top, endPoint: .bottom)
    }

    private func deltaLabel(_ value: Double) -> some View {
        let positive = value >= 0
        return HStack(spacing: 2) {
            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.weight(.bold))
            Text(String(format: "%+.1f%%", value))
                .font(.caption.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(positive ? .red : .green)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            Capsule().fill((positive ? Color.red : Color.green).opacity(0.12))
        }
    }
}
