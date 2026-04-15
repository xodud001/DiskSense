import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            List(SidebarTab.allCases, selection: $state.selectedTab) { tab in
                Label(tab.title, systemImage: tab.systemImage).tag(tab)
            }
            .navigationTitle("DiskSense")
            .frame(minWidth: 180)
        } detail: {
            switch appState.selectedTab {
            case .dashboard: DashboardView()
            case .analysis:  AnalysisView()
            case .history:   HistoryView()
            case .settings:  SettingsView()
            }
        }
    }
}
