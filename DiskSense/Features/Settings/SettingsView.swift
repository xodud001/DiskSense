import SwiftUI
import UserNotifications

struct SettingsView: View {
    @State private var selectedModelId: String = SettingsStore.selectedModelId
    @State private var deleteMode: SettingsStore.DeleteMode = SettingsStore.deleteMode
    @State private var autoRescanHours: Double = SettingsStore.autoRescanHours
    @State private var thresholds: [Double] = SettingsStore.thresholds
    @State private var notificationsEnabled: Bool = SettingsStore.notificationsEnabled
    @State private var refreshToken: Int = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("설정").font(.system(size: 28, weight: .bold, design: .rounded))

                modelSection
                providersSection
                cleanupSection
                rescanSection
                notificationsSection
                dataSection
            }
            .padding(24)
        }
        .navigationTitle("")
    }

    // MARK: - Model

    private var modelSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("현재 모델", systemImage: "cpu")
                    .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                Picker("모델", selection: $selectedModelId) {
                    ForEach(AIProvider.allCases) { provider in
                        Section(provider.displayName) {
                            ForEach(ModelRegistry.models(for: provider)) { m in
                                HStack {
                                    Text(m.displayName)
                                    if !m.isAvailable {
                                        Text("· 키 필요").foregroundStyle(.tertiary)
                                    }
                                }
                                .tag(m.id)
                            }
                        }
                    }
                }
                .labelsHidden()
                .onChange(of: selectedModelId) { _, new in SettingsStore.selectedModelId = new }

                if let model = ModelRegistry.find(selectedModelId) {
                    HStack(spacing: 10) {
                        providerBadge(model.provider)
                        Text(model.displayName).font(.callout)
                        Spacer()
                        Text(String(format: "입력 $%.2f · 출력 $%.2f / MTok",
                                    model.inputCostPerMTok, model.outputCostPerMTok))
                            .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    }
                    if !model.isAvailable {
                        Text("⚠️ \(model.provider.displayName) API 키가 없습니다. 아래에서 추가하세요.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .padding(10)
        }
    }

    private func providerBadge(_ provider: AIProvider) -> some View {
        HStack(spacing: 4) {
            Circle().fill(provider.isConfigured ? Color.green : Color.secondary).frame(width: 6, height: 6)
            Text(provider.displayName).font(.caption2)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    // MARK: - Providers

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API 키").font(.system(size: 18, weight: .semibold, design: .rounded))
            ForEach(AIProvider.allCases) { provider in
                ProviderKeyBox(provider: provider, refreshToken: $refreshToken)
            }
        }
    }

    // MARK: - Cleanup

    private var cleanupSection: some View {
        GroupBox("삭제 방식") {
            Picker("삭제 방식", selection: $deleteMode) {
                ForEach(SettingsStore.DeleteMode.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .padding(8)
            .onChange(of: deleteMode) { _, new in SettingsStore.deleteMode = new }
        }
    }

    // MARK: - Rescan

    private var rescanSection: some View {
        GroupBox("자동 재스캔") {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(autoRescanHours))시간마다")
                Slider(value: $autoRescanHours, in: 1...48, step: 1)
                    .onChange(of: autoRescanHours) { _, new in SettingsStore.autoRescanHours = new }
            }
            .padding(8)
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        GroupBox("알림 임계치") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("알림 활성화", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, new in
                        SettingsStore.notificationsEnabled = new
                        if new {
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                        }
                    }
                thresholdSlider("주의", idx: 0, color: .yellow)
                thresholdSlider("경고", idx: 1, color: .orange)
                thresholdSlider("위험", idx: 2, color: .red)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func thresholdSlider(_ label: String, idx: Int, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(Int(thresholds[idx] * 100))%").frame(width: 110, alignment: .leading)
            Slider(value: Binding(
                get: { thresholds[idx] },
                set: { thresholds[idx] = $0; SettingsStore.thresholds = thresholds }
            ), in: 0.5...1.0)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        GroupBox("데이터") {
            HStack {
                Button("캐시 초기화") { ScanCache.clear() }
                Button("스냅샷 폴더 열기") {
                    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        .appendingPathComponent("DiskSense/Snapshots")
                    NSWorkspace.shared.open(url)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - ProviderKeyBox

private struct ProviderKeyBox: View {
    let provider: AIProvider
    @Binding var refreshToken: Int
    @State private var input: String = ""
    @State private var hasKey: Bool = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(hasKey ? Color.green : Color.orange).frame(width: 7, height: 7)
                    Text(provider.displayName).font(.callout.weight(.semibold))
                    Spacer()
                    if hasKey {
                        Text("저장됨").font(.caption).foregroundStyle(.green)
                    } else {
                        Text("미설정").font(.caption).foregroundStyle(.orange)
                    }
                }
                HStack {
                    SecureField(provider.keyPrefix.isEmpty ? "API 키" : "\(provider.keyPrefix)...", text: $input)
                        .textFieldStyle(.roundedBorder)
                    Button("저장") { save() }.disabled(input.isEmpty)
                    if hasKey {
                        Button("삭제", role: .destructive) {
                            KeychainHelper.delete(key: provider.keychainKey)
                            refreshState()
                        }
                    }
                }
                Link("API 키 발급받기", destination: provider.apiKeyHelpURL)
                    .font(.caption)
            }
            .padding(8)
        }
        .onAppear(perform: refreshState)
        .onChange(of: refreshToken) { _, _ in refreshState() }
    }

    private func save() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? KeychainHelper.save(key: provider.keychainKey, value: trimmed)
        input = ""
        refreshState()
        refreshToken += 1
    }

    private func refreshState() {
        hasKey = provider.isConfigured
    }
}
