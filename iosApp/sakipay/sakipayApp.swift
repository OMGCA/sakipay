/* (c) Copyright XiatStudio 2026~2026 */
import SwiftUI
import SwiftData
import WidgetKit

@main
struct sakipayApp: App {
    @StateObject private var vm = DashboardViewModel()
    @Environment(\.scenePhase) private var scenePhase

    private let modelContainer: ModelContainer = {
        let schema = Schema([EarningsConfig.self])
        let storeURL = URL.documentsDirectory.appending(path: "sakipay.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Store is corrupted from a previous crash — delete and recreate
            print("[sakipay] ModelContainer failed: \(error). Recreating store.")
            try? FileManager.default.removeItem(at: storeURL)
            if let retry = try? ModelContainer(for: schema, configurations: [config]) {
                return retry
            }
            // Last resort: in-memory
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: schema, configurations: [fallback]) else {
                fatalError("ModelContainer creation failed — check disk space and permissions")
            }
            return container
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                vm.refresh()
            case .background:
                WidgetCenter.shared.reloadAllTimelines()
            default:
                break
            }
        }
    }
}
