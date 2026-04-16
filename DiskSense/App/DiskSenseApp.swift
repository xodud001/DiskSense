import SwiftUI
import SwiftData

@main
struct DiskSenseApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            SnapshotWiringView(appState: appState)
                .frame(minWidth: 1100, minHeight: 680)
                .task { appState.bootstrap() }
        }
        .modelContainer(for: [CleanupHistory.self, StorageSnapshot.self])
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}

/// modelContext를 AppState.onScanCompleted 콜백에 연결하는 래퍼 뷰.
private struct SnapshotWiringView: View {
    let appState: AppState
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ContentView()
            .environment(appState)
            .onAppear {
                appState.onSnapshot = { [modelContext] capacity, used, kind, itemCount, duration, topCats in
                    let snapshot = StorageSnapshot(
                        totalCapacity: capacity,
                        totalUsed: used,
                        kind: kind,
                        scanItemCount: itemCount,
                        scanDuration: duration,
                        scanTopCategories: topCats
                    )
                    modelContext.insert(snapshot)
                    try? modelContext.save()
                }
            }
    }
}

private struct MenuBarLabel: View {
    let appState: AppState

    private var ratio: Double {
        if let u = appState.volumeUsage, u.total > 0 {
            return Double(u.used) / Double(u.total)
        }
        if let r = appState.scanResult, r.totalCapacity > 0 {
            return Double(r.totalUsed) / Double(r.totalCapacity)
        }
        return 0
    }

    private var percent: Int { Int(ratio * 100) }

    var body: some View {
        if appState.volumeUsage != nil || appState.scanResult != nil {
            Text("\(percent)%")
        } else {
            Image(systemName: "externaldrive")
        }
    }
}
