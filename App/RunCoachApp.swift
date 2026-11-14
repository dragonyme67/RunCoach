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
        let sync = SyncEngine(container: container, store: KeychainTokenStore(), http: URLSessionHTTPClient())
        let coach = CoachService(container: container)
        coach.onPlanChanged = { Task { await sync.pushWorkouts() } }
        _sync = State(initialValue: sync)
        _coach = State(initialValue: coach)
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
                    await Run.fillMissingBests(context: container.mainContext)
                    // Données factices des captures : on ne touche pas au plan de démonstration.
                    guard !options.mockData else { return }
                    coach.updatePlanStatus()
                    await coach.autoGenerateIfNeeded()
                    WidgetBridge.update(context: container.mainContext)
                }
            case .background:
                BackgroundSync.schedule()
                if !options.mockData {
                    WidgetBridge.update(context: container.mainContext)
                    Task { await Notifications.reschedule(context: container.mainContext) }
                }
            default: break
            }
        }
        .backgroundTask(.appRefresh(BackgroundSync.identifier)) { [engine = sync] in
            BackgroundSync.schedule()
            await engine.sync(background: true)
        }
    }
}
