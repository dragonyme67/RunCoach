import SwiftUI
import SwiftData

struct RootView: View {
    let options: LaunchOptions
    @Query private var profiles: [AthleteProfile]

    var body: some View {
        if let screen = options.screen {
            DebugScreen(name: screen)
        } else if profiles.first?.medicalDisclaimerAcceptedAt == nil {
            // L'onboarding enregistre le profil : la requête se met à jour et les onglets s'affichent.
            OnboardingFlow(onFinish: {})
        } else {
            MainTabs()
        }
    }
}

/// Les 5 onglets. Réglages s'ouvre depuis l'avatar de l'écran Aujourd'hui.
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
            NavigationStack { RunListView().rcDestinations() }
                .tabItem { Label("Activités", systemImage: "figure.run") }
                .tag(2)
            NavigationStack { CoachChatView() }
                .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(3)
            NavigationStack { ProgressScreen().rcDestinations() }
                .tabItem { Label("Progrès", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(4)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

extension View {
    /// Destinations communes à toutes les piles de navigation.
    /// Dans une pile, tous les liens passent par une valeur : après un `NavigationLink { vue }`,
    /// un `NavigationLink(value:)` rouvrait l'écran précédent au lieu du détail (constat sur iPhone).
    func rcDestinations() -> some View {
        self
            .navigationDestination(for: PlannedWorkout.self) { PlannedWorkoutDetailView(workout: $0) }
            .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
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
                if let run = runs.first(where: { !$0.isStrength }) { RunDetailView(run: run) }
            }
        case "activity":
            NavigationStack {
                if let run = runs.first(where: { $0.isStrength }) { RunDetailView(run: run) }
            }
        case "activities":
            NavigationStack { RunListView().rcDestinations() }
        case "replay":
            if let run = runs.first(where: { !$0.isStrength }) { ReplayView(run: run) }
        case "replaymap":
            if let run = runs.first(where: { !$0.isStrength }) { ReplayView(run: run, style: 1) }
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
