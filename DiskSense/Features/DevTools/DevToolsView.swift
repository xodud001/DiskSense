import SwiftUI
import SwiftData

struct DevToolsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var isScanning = false
    @State private var selection: Set<UUID> = []
    @State private var showConfirm = false
    @State private var executing = false
    @State private var lastResult: CleanupResult?

    private var selectedHits: [DevToolHit] {
        appState.devToolHits.filter { selection.contains($0.id) }
    }
    private var selectedBytes: Int64 { selectedHits.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if appState.devToolHits.isEmpty && !isScanning {
                ContentUnavailableView(
                    "스캔 결과가 없습니다",
                    systemImage: "hammer",
                    description: Text("node_modules, DerivedData, Pods 등 개발 환경 캐시를 탐색합니다.")
                )
            } else {
                actionBar
                List(appState.devToolHits, selection: $selection) { hit in
                    DevToolRow(hit: hit, selected: selection.contains(hit.id))
                        .tag(hit.id)
                }
                .listStyle(.inset)
            }
            if let r = lastResult {
                GroupBox {
                    Text("정리 완료: \(ByteFormatter.string(r.totalBytesFreed)) 확보, 실패 \(r.failures.count)건")
                        .font(.callout)
                }
            }
        }
        .padding(24)
        .navigationTitle("")
        .confirmationDialog(
            "선택한 \(selection.count)개 항목을 휴지통으로 이동합니다 (\(ByteFormatter.string(selectedBytes)))",
            isPresented: $showConfirm
        ) {
            Button("휴지통으로 이동", role: .destructive) { Task { await execute() } }
            Button("취소", role: .cancel) { }
        } message: {
            Text("node_modules, DerivedData 등은 빌드 시 재생성됩니다.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("개발환경 캐시").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("재생성 가능한 빌드 아티팩트만 필터링합니다").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    isScanning = true
                    await appState.scanDevTools()
                    isScanning = false
                }
            } label: {
                Label(isScanning ? "스캔 중..." : "스캔", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isScanning)
        }
    }

    private var actionBar: some View {
        HStack {
            Text("\(appState.devToolHits.count)개 발견 · 총 \(ByteFormatter.string(appState.devToolHits.reduce(0) { $0 + $1.sizeBytes }))")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("전체 선택") { selection = Set(appState.devToolHits.map { $0.id }) }
                .buttonStyle(.bordered)
            Button("선택 해제") { selection.removeAll() }
                .buttonStyle(.bordered).disabled(selection.isEmpty)
            Button {
                showConfirm = true
            } label: {
                Label("선택 정리", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection.isEmpty || executing)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
    }

    private func execute() async {
        executing = true
        defer { executing = false }
        let suggestions = selectedHits.map {
            AISuggestion(
                targetPaths: [$0.path],
                estimatedBytes: $0.sizeBytes,
                reason: "\($0.kind.rawValue) — 개발 캐시, 재빌드 시 재생성됨",
                risk: .safe,
                recoverable: true,
                isApproved: true
            )
        }
        SnapshotManager.write(suggestions: suggestions)
        let r = await CleanupExecutor.execute(suggestions: suggestions, mode: .trash)
        lastResult = r

        let history = CleanupHistory(
            executedAt: .now,
            totalSizeFreed: r.totalBytesFreed,
            itemCount: r.succeededPaths.count,
            suggestions: suggestions
        )
        modelContext.insert(history)
        try? modelContext.save()

        appState.devToolHits.removeAll { h in r.succeededPaths.contains(h.path) }
        selection.removeAll()
    }
}

private struct DevToolRow: View {
    let hit: DevToolHit
    let selected: Bool

    var body: some View {
        HStack {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.kind.rawValue).font(.callout.bold())
                Text(hit.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormatter.string(hit.sizeBytes))
                .font(.callout.bold()).monospacedDigit().foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
    }
}
