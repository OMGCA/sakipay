/* (c) Copyright XiatStudio 2026~2026 */
import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var vm: DashboardViewModel
    @Query private var configs: [EarningsConfig]
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("今日", systemImage: "dollarsign.circle.fill")
                }
                .tag(0)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(1)
        }
        .task { syncConfig() }
        .onChange(of: configs.first?.updatedAt) { _, _ in syncConfig() }
    }

    private func syncConfig() {
        guard let config = configs.first else { return }
        // modelContext check defends against accessing a model whose backing
        // NSManagedObject has been deallocated (e.g. stale @Query after store reset)
        guard config.modelContext != nil, config.monthlyPay > 0 else { return }
        vm.configure(with: config)
    }
}
