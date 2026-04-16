import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var categoryFilter: StorageCategory? = nil
    @State private var hoveredLabel: String? = nil

    private var breakdown: [StorageCategory: Int64] {
        appState.scanResult?.breakdown ?? appState.liveBreakdown
    }
    private var scannedBytes: Int64 {
        appState.scanResult?.totalUsed ?? appState.liveBytesScanned
    }
    private var volumeUsedBytes: Int64 {
        appState.volumeUsage?.used ?? scannedBytes
    }
    private var capacityBytes: Int64 {
        appState.volumeUsage?.total ?? appState.scanResult?.totalCapacity ?? 0
    }
    private var availableBytes: Int64 {
        appState.volumeUsage?.available ?? max(0, capacityBytes - volumeUsedBytes)
    }
    private var unaccountedBytes: Int64 {
        max(0, volumeUsedBytes - scannedBytes)
    }
    private var items: [DiskItem] {
        appState.scanResult?.items ?? appState.liveItems
    }
    private var hasData: Bool {
        appState.isScanning || !items.isEmpty || appState.scanResult != nil
    }
    private var usageRatio: Double {
        guard capacityBytes > 0 else { return 0 }
        return min(1.0, Double(volumeUsedBytes) / Double(capacityBytes))
    }
    private var ratioColor: Color {
        switch usageRatio {
        case 0..<0.70:    return .green
        case 0.70..<0.85: return .yellow
        case 0.85..<0.95: return .orange
        default:          return .red
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topBar
                if hasData {
                    storageCard
                    coverageFooter
                    StorageTrendChart()
                    categoriesSection
                    topItemsSection
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("")
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DiskSense")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                fdaBadge
            }
            Spacer()
        }
    }

    private var fdaBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(appState.hasFullDiskAccess ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(appState.hasFullDiskAccess ? "Full Disk Access 활성" : "Full Disk Access 비활성")
                .font(.caption).foregroundStyle(.secondary)
            if !appState.hasFullDiskAccess {
                Button("설정") { PermissionChecker.openFullDiskAccessPreferences() }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }

    // MARK: - Storage card (main hero)

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            cardHeader
            if appState.isScanning {
                scanProgressBlock
            } else {
                storageSummary
            }
            StorageGaugeView(
                used: volumeUsedBytes,
                capacity: capacityBytes,
                breakdown: breakdown,
                hoveredLabel: $hoveredLabel
            )
            SegmentLegend(
                segments: StorageGaugeView.computeSegments(
                    used: volumeUsedBytes, capacity: capacityBytes, breakdown: breakdown
                ),
                availableBytes: availableBytes,
                hoveredLabel: $hoveredLabel
            )
            primaryCTA
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        }
    }

    private var cardHeader: some View {
        HStack {
            Label("저장공간", systemImage: "internaldrive.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if appState.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Button(role: .cancel) {
                        appState.cancelScan()
                    } label: {
                        Label("취소", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Button {
                    Task { await appState.startScan() }
                } label: {
                    Label("다시 스캔", systemImage: "arrow.clockwise")
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    private var storageSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ByteFormatter.string(volumeUsedBytes))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("사용 중").font(.callout).foregroundStyle(.secondary)
                }
                Text("총 용량 \(ByteFormatter.string(capacityBytes))")
                    .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(usageRatio * 100))%")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ratioColor)
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("\(ByteFormatter.string(availableBytes)) 여유")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }

    private var scanProgressBlock: some View {
        let target = Int64(Double(appState.volumeUsage?.used ?? 0) * 0.95)
        let effectiveTarget = max(target, 1)
        let ratio = min(1.0, Double(appState.liveBytesScanned) / Double(effectiveTarget))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(ratio * 100))%")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("스캔 중").font(.callout).foregroundStyle(.secondary)
                Text(String(format: "⏱ %.1fs", appState.liveElapsed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(ByteFormatter.string(appState.liveBytesScanned)) / \(ByteFormatter.string(target))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(appState.liveCurrentPath)
                .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.middle)
            if let last = appState.lastScanDuration, !appState.isScanning {
                Text(String(format: "마지막 스캔: %.2fs", last))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var primaryCTA: some View {
        HStack {
            Button {
                appState.selectedTab = .analysis
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("AI로 정리 제안 받기").fontWeight(.semibold)
                    Image(systemName: "arrow.right").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(items.isEmpty || appState.isScanning)
            Spacer()
        }
    }

    private var coverageFooter: some View {
        HStack(spacing: 14) {
            if let r = appState.scanResult {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.caption2)
                    Text("마지막 스캔 \(r.scannedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
            if unaccountedBytes > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill").font(.caption2)
                    Text("분석됨 \(ByteFormatter.string(scannedBytes)) · 미분석 \(ByteFormatter.string(unaccountedBytes))")
                        .font(.caption2).monospacedDigit()
                }
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("AI는 파일 메타데이터만 전송 · 내용 X")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("카테고리 별").font(.system(size: 18, weight: .semibold, design: .rounded))
                if categoryFilter != nil {
                    Button("필터 해제") { categoryFilter = nil }
                        .buttonStyle(.borderless).font(.caption)
                }
                Spacer()
            }
            CategoryBreakdownView(
                breakdown: breakdown,
                total: volumeUsedBytes > 0 ? volumeUsedBytes : scannedBytes,
                selected: Binding(
                    get: { categoryFilter },
                    set: { categoryFilter = $0 }
                )
            )
        }
    }

    // MARK: - Top items

    private var topItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(categoryFilter.map { "용량 큰 \($0.displayName) 항목" } ?? "용량 큰 항목")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer()
                Text("Top 30").font(.caption).foregroundStyle(.tertiary)
            }
            TopItemsView(items: items, filter: categoryFilter, maxCount: 30)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 44)).foregroundStyle(.tertiary)
            Text("스캔을 시작해 저장공간을 분석하세요")
                .font(.title3.bold())
            Text("홈 디렉토리를 재귀적으로 탐색해 카테고리별 용량을 집계합니다")
                .font(.callout).foregroundStyle(.secondary)
            Button {
                Task { await appState.startScan() }
            } label: {
                Label("스캔 시작", systemImage: "magnifyingglass")
                    .frame(maxWidth: 220).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 80)
    }
}
