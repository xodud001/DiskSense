import SwiftUI
import SwiftData

@main
struct DiskSenseApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 1100, minHeight: 680)
                .task { appState.bootstrap() }
        }
        .modelContainer(for: CleanupHistory.self)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
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
