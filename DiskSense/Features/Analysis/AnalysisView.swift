import SwiftUI
import SwiftData

struct AnalysisView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CleanupHistory.executedAt, order: .reverse) private var history: [CleanupHistory]

    @State private var events: [AgentEvent] = []
    @State private var isRunning: Bool = false
    @State private var agent: AIAgent? = nil
    @State private var proposals: [AISuggestion] = []
    @State private var showApproval = false
    @State private var executing = false
    @State private var lastResult: CleanupResult?
    @State private var errorMessage: String?
    @State private var selectedModelId: String = SettingsStore.selectedModelId
    @State private var tokensUsed: (input: Int, output: Int) = (0, 0)
    @State private var estimatedCost: Double = 0

    private var selectedModel: AIModel {
        ModelRegistry.find(selectedModelId) ?? ModelRegistry.default
    }
    private var modelAvailable: Bool { selectedModel.isAvailable }

    private var approvedCount: Int { proposals.filter { $0.isApproved }.count }
    private var approvedBytes: Int64 {
        proposals.filter { $0.isApproved }.reduce(0) { $0 + $1.estimatedBytes }
    }

    var body: some View {
        HSplitView {
            leftPane.frame(minWidth: 340, idealWidth: 480)
            rightPane.frame(minWidth: 300, idealWidth: 360)
        }
        .frame(minWidth: 680)
        .sheet(isPresented: $showApproval) {
            ApprovalSheet(
                suggestions: proposals,
                mode: SettingsStore.deleteMode == .permanent ? .permanent : .trash,
                onConfirm: { showApproval = false; Task { await execute() } },
                onCancel: { showApproval = false }
            )
        }
        .navigationTitle("")
    }

    // MARK: - Left pane

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBar
            modelSelector
            if events.isEmpty && !isRunning {
                emptyFeed
            } else {
                AgentFeedView(events: events)
            }
        }
        .padding(20)
    }

    private var headerBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 분석").font(.system(size: 26, weight: .bold, design: .rounded))
                Text(modelAvailable
                     ? "에이전트 모드 · 툴 10개 · multi-step 추론"
                     : "선택된 모델의 API 키가 없습니다")
                    .font(.caption).foregroundStyle(modelAvailable ? Color.secondary : Color.orange)
            }
            Spacer()
            if isRunning {
                Button(role: .cancel) {
                    Task { await agent?.cancel() }
                } label: {
                    Label("중지", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await start() }
                } label: {
                    Label(events.isEmpty ? "분석 시작" : "재실행",
                          systemImage: modelAvailable ? "sparkles" : "list.bullet.rectangle")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(appState.scanResult?.items.isEmpty ?? true)
            }
        }
    }

    private var modelSelector: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(modelAvailable ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(selectedModel.provider.displayName)
                .font(.caption2).foregroundStyle(.secondary)
            Text("·").font(.caption2).foregroundStyle(.tertiary)
            Menu {
                ForEach(AIProvider.allCases) { provider in
                    Section(provider.displayName) {
                        ForEach(ModelRegistry.models(for: provider)) { m in
                            Button {
                                selectedModelId = m.id
                                SettingsStore.selectedModelId = m.id
                            } label: {
                                if selectedModelId == m.id {
                                    Label(m.displayName, systemImage: "checkmark")
                                } else {
                                    Text(m.isAvailable ? m.displayName : "\(m.displayName) (키 필요)")
                                }
                            }
                            .disabled(!m.isAvailable && selectedModelId != m.id)
                        }
                    }
                }
                Divider()
                Button("설정에서 API 키 등록") { appState.selectedTab = .settings }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedModel.displayName).font(.callout.weight(.medium))
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            if tokensUsed.input + tokensUsed.output > 0 {
                Text("입력 \(tokensUsed.input.formatted()) · 출력 \(tokensUsed.output.formatted()) · \(String(format: "$%.4f", estimatedCost))")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
    }

    private var emptyFeed: some View {
        VStack(spacing: 12) {
            Image(systemName: modelAvailable ? "wand.and.rays" : "key.slash")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            if modelAvailable {
                Text("\(selectedModel.displayName) 에이전트가 홈 디렉토리를 조사하여 정리 제안을 생성합니다")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("툴 10개를 활용해 폴더를 직접 조사하고 증거 기반으로 제안합니다")
                    .font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("\(selectedModel.provider.displayName) API 키가 필요합니다").font(.callout.bold())
                Button("설정에서 키 등록하기") { appState.selectedTab = .settings }
                    .buttonStyle(.bordered)
                Divider().padding(.vertical, 6).frame(width: 200)
                Text("키 없이 룰 기반 로컬 분석으로 대체 가능").font(.caption2).foregroundStyle(.tertiary)
                Button("룰 기반 분석 실행") { Task { await runOfflineFallback() } }
                    .buttonStyle(.link).font(.caption)
            }
            if appState.scanResult == nil {
                Button("먼저 스캔하기") { appState.selectedTab = .dashboard }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    // MARK: - Right pane

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("제안").font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("\(proposals.count)개").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                Spacer()
                if !proposals.isEmpty {
                    Menu {
                        Button("안전 항목 전체 선택") {
                            for i in proposals.indices where proposals[i].risk == .safe {
                                proposals[i].isApproved = true
                            }
                        }
                        Button("전체 선택") { for i in proposals.indices { proposals[i].isApproved = true } }
                        Button("전체 해제") { for i in proposals.indices { proposals[i].isApproved = false } }
                    } label: { Image(systemName: "checkmark.circle").font(.callout) }
                    .menuStyle(.borderlessButton).frame(width: 28)
                }
            }
            .padding(.horizontal, 20).padding(.top, 20)

            if proposals.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "lightbulb").font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text("분석 중에 제안이 누적됩니다").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($proposals) { $s in SuggestionCard(suggestion: $s) }
                    }
                    .padding(.horizontal, 20)
                }
            }

            if !proposals.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("승인 \(approvedCount)개 · 절약 예상")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(ByteFormatter.string(approvedBytes))
                            .font(.callout.bold()).monospacedDigit()
                    }
                    Button {
                        showApproval = true
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("선택 정리 실행").fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(approvedCount == 0 || executing)

                    if let err = errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    if let r = lastResult {
                        Text("실행 완료 · \(ByteFormatter.string(r.totalBytesFreed)) 정리 · 성공 \(r.succeededPaths.count) · 실패 \(r.failures.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Actions

    private func start() async {
        errorMessage = nil
        events = []
        proposals = []
        lastResult = nil
        tokensUsed = (0, 0)
        estimatedCost = 0

        guard let scanResult = appState.scanResult, !scanResult.items.isEmpty else {
            errorMessage = "스캔 결과가 없습니다. 대시보드에서 스캔을 먼저 실행해주세요."
            return
        }

        guard modelAvailable else {
            await runOfflineFallback()
            return
        }

        isRunning = true
        defer { isRunning = false }

        let agent = AIAgent()
        self.agent = agent
        let initial = AgentPromptBuilder.buildInitialContext(
            scanResult: scanResult,
            volumeUsage: appState.volumeUsage
        )
        let historySnapshots: [HistorySnapshot] = history.map {
            HistorySnapshot(
                executedAt: $0.executedAt,
                totalSizeFreed: $0.totalSizeFreed,
                itemCount: $0.itemCount,
                suggestions: $0.suggestions
            )
        }
        let model = selectedModel

        do {
            let result = try await agent.run(
                model: model,
                initialContext: initial,
                historyProvider: { historySnapshots },
                eventEmitter: { event in
                    Task { @MainActor in
                        events.append(event)
                        if case let .proposal(_, s) = event {
                            proposals.append(s)
                        }
                    }
                }
            )
            tokensUsed = (result.inputTokens, result.outputTokens)
            estimatedCost = result.estimatedCostUSD
        } catch is CancellationError {
            events.append(.error(message: "사용자 중지"))
        } catch {
            errorMessage = "에이전트 실행 실패: \(error.localizedDescription)"
            events.append(.error(message: error.localizedDescription))
        }
    }

    private func runOfflineFallback() async {
        guard let scanResult = appState.scanResult, !scanResult.items.isEmpty else { return }
        events.append(.thinking(text: "룰 기반 로컬 분석 — API 키 없이 확장자/나이/카테고리 규칙으로 제안을 생성합니다."))
        let fallback = OfflineFallback.suggest(items: scanResult.items)
        proposals = fallback
        for s in fallback { events.append(.proposal(suggestion: s)) }
        let totalBytes = fallback.reduce(Int64(0)) { $0 + $1.estimatedBytes }
        events.append(.finished(summary: "룰 기반 분석 완료: \(fallback.count)개 제안, 약 \(ByteFormatter.string(totalBytes)) 정리 가능"))
    }

    private func execute() async {
        executing = true
        defer { executing = false }
        SnapshotManager.write(suggestions: proposals.filter { $0.isApproved })
        let mode: CleanupMode = SettingsStore.deleteMode == .permanent ? .permanent : .trash
        let result = await CleanupExecutor.execute(suggestions: proposals, mode: mode)
        lastResult = result

        let h = CleanupHistory(
            executedAt: .now,
            totalSizeFreed: result.totalBytesFreed,
            itemCount: result.succeededPaths.count,
            suggestions: proposals.filter { $0.isApproved }
        )
        modelContext.insert(h)
        try? modelContext.save()

        proposals.removeAll { s in
            s.isApproved && s.targetPaths.allSatisfy { result.succeededPaths.contains($0) }
        }
    }
}
