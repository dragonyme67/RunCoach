import SwiftUI
import SwiftData

/// Options de lancement utilisées par les captures d'écran de la CI :
/// `-screen <nom>` affiche directement un écran, `-scheme light|dark` force l'apparence.
struct LaunchOptions {
    var screen: String?
    var colorScheme: ColorScheme?

    static var current: LaunchOptions {
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        var options = LaunchOptions()
        options.screen = value(after: "-screen")
        switch value(after: "-scheme") {
        case "dark": options.colorScheme = .dark
        case "light": options.colorScheme = .light
        default: break
        }
        return options
    }
}

enum AppEnvironment {
    static let schema = Schema([
        AthleteProfile.self, Goal.self, Run.self, Split.self, RunTrack.self,
        DailyMetric.self, TrainingPlan.self, PlannedWorkout.self, ChatMessage.self, SyncState.self
    ])

    // shortcut: base en mémoire remplie de données factices à chaque lancement ;
    // l'étape 2 passe à une base persistante et garde ce mode derrière `-mockData`.
    @MainActor
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            MockData.seed(into: container.mainContext)
            return container
        } catch {
            fatalError("Impossible de créer la base locale : \(error)")
        }
    }
}
