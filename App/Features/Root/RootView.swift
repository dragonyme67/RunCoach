import SwiftUI
import SwiftData

struct RootView: View {
    let options: LaunchOptions

    var body: some View {
        if let screen = options.screen {
            DebugScreen(name: screen)
        } else {
            MainTabs()
        }
    }
}

/// Les 4 onglets. Réglages s'ouvre depuis l'avatar de l'écran Aujourd'hui.
struct MainTabs: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { TodayView().rcDestinations() }
                .tabItem { Label("Aujourd'hui", systemImage: "sun.max.fill") }
                .tag(0)
            NavigationStack { PlanView().rcDestinations() }
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(1)
            NavigationStack { CoachChatView() }
                .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(2)
            NavigationStack { ProgressScreen().rcDestinations() }
                .tabItem { Label("Progrès", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(3)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Écrans sans donnée associée. Dans une pile, tous les liens passent par une valeur : après un
/// `NavigationLink { vue }`, un `NavigationLink(value:)` rouvrait la liste au lieu du détail (constat sur iPhone).
enum Route: Hashable {
    case runList
}

extension View {
    /// Destinations communes à toutes les piles de navigation.
    func rcDestinations() -> some View {
        self
            .navigationDestination(for: PlannedWorkout.self) { PlannedWorkoutDetailView(workout: $0) }
            .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
            .navigationDestination(for: Route.self) { _ in RunListView() }
    }
}

/// Affiche directement un écran donné : sert aux captures d'écran de la CI (`-screen <nom>`).
struct DebugScreen: View {
    let name: String
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @Query(sort: \PlannedWorkout.dayKey) private var workouts: [PlannedWorkout]

    var body: some View {
        switch name {
        case "onboarding":
            OnboardingFlow(onFinish: {})
        case "plan":
            NavigationStack { PlanView().rcDestinations() }
        case "planned":
            NavigationStack {
                if let workout = workouts.first(where: { $0.kind == "intervals" }) ?? workouts.first {
                    PlannedWorkoutDetailView(workout: workout)
                }
            }
        case "strength":
            NavigationStack {
                if let workout = workouts.first(where: { $0.kind == "strength" && $0.status == "planned" }) {
                    PlannedWorkoutDetailView(workout: workout)
                }
            }
        case "run":
            NavigationStack {
                if let run = runs.first { RunDetailView(run: run) }
            }
        case "replay":
            if let run = runs.first { ReplayView(run: run) }
        case "replaymap":
            if let run = runs.first { ReplayView(run: run, style: 1) }
        case "coach":
            NavigationStack { CoachChatView() }
        case "progress":
            NavigationStack { ProgressScreen().rcDestinations() }
        case "settings":
            NavigationStack { SettingsView() }
        case "tabs":
            MainTabs()
        default:
            NavigationStack { TodayView().rcDestinations() }
        }
    }
}
