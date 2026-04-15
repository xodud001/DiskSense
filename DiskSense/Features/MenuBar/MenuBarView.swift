import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    private var used: Int64 { appState.volumeUsage?.used ?? appState.scanResult?.totalUsed ?? 0 }
    private var capacity: Int64 { appState.volumeUsage?.total ?? appState.scanResult?.totalCapacity ?? 0 }
    private var ratio: Double {
        guard capacity > 0 else { return 0 }
        return min(1.0, Double(used) / Double(capacity))
    }
    private var breakdown: [StorageCategory: Int64] {
        appState.scanResult?.breakdown ?? appState.liveBreakdown
    }
    private var available: Int64 { appState.volumeUsage?.available ?? max(0, capacity - used) }

    private var percentColor: Color {
        switch ratio {
        case 0..<0.70: return .green
        case 0.70..<0.85: return .yellow
        case 0.85..<0.95: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DiskSense").font(.headline)
                Spacer()
                if appState.isScanning {
                    ProgressView().controlSize(.small)
                }
            }
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ByteFormatter.string(used))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("사용 중").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(ratio * 100))%")
                        .font(.callout.bold()).monospacedDigit()
                        .foregroundStyle(percentColor)
                }

                StorageMiniGauge(used: used, capacity: capacity, breakdown: breakdown)

                HStack {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 5, height: 5)
                        Text("\(ByteFormatter.string(available)) 여유")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    Text("총 \(ByteFormatter.string(capacity))")
                        .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }
            }

            if !breakdown.isEmpty {
                Divider()
                VStack(spacing: 4) {
                    let topCats = breakdown.sorted { $0.value > $1.value }.prefix(3)
                    ForEach(Array(topCats), id: \.key) { cat, bytes in
                        HStack(spacing: 8) {
                            Circle().fill(cat.color).frame(width: 6, height: 6)
                            Text(cat.displayName).font(.caption)
                            Spacer()
                            Text(ByteFormatter.string(bytes))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            menuButton(icon: "arrow.clockwise", text: "지금 스캔") {
                Task { await appState.startScan() }
                openMainWindow()
            }
            menuButton(icon: "macwindow", text: "메인 윈도우 열기") {
                openMainWindow()
            }

            Divider()

            menuButton(icon: "power", text: "DiskSense 종료") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder
    private func menuButton(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(.primary)
                Text(text)
                    .font(.callout)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
