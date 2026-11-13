import SwiftUI
import SwiftData

@main
struct RunCoachApp: App {
    private let container: ModelContainer
    private let options: LaunchOptions
    @State private var sync: SyncEngine
    @State private var coach: CoachService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let options = LaunchOptions.current
        let container = AppEnvironment.makeContainer(mock: options.mockData)
        self.options = options
        self.container = container
        _sync = State(initialValue: SyncEngine(container: container, store: KeychainTokenStore(), http: URLSessionHTTPClient()))
        _coach = State(initialValue: CoachService(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView(options: options)
                .preferredColorScheme(options.colorScheme)
                .tint(Color.rc.accentText)
                // Interface en français quelle que soit la langue du téléphone (dates, graphiques, sélecteurs).
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .environment(sync)
                .environment(coach)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await sync.syncIfStale()
                    // Données factices des captures : on ne touche pas au plan de démonstration.
                    guard !options.mockData else { return }
                    coach.updatePlanStatus()
                    await coach.autoGenerateIfNeeded()
                }
            case .background: BackgroundSync.schedule()
            default: break
            }
        }
        .backgroundTask(.appRefresh(BackgroundSync.identifier)) { [engine = sync] in
            BackgroundSync.schedule()
            await engine.sync(background: true)
        }
    }
}
