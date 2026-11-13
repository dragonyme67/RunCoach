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
/// Glisser depuis le bord gauche d'un écran d'onglet ramène à l'onglet précédent (demande de l'utilisateur, 2026-11-13).
struct MainTabs: View {
    @State private var selection = 0
    /// Onglets visités, du plus ancien au plus récent.
    @State private var history: [Int] = []
    @State private var isGoingBack = false

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { TodayView().rcDestinations().backSwipe(goBack) }
                .tabItem { Label("Aujourd'hui", systemImage: "sun.max.fill") }
                .tag(0)
            NavigationStack { PlanView().rcDestinations().backSwipe(goBack) }
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(1)
            NavigationStack { RunListView().rcDestinations().backSwipe(goBack) }
                .tabItem { Label("Activités", systemImage: "figure.run") }
                .tag(2)
            NavigationStack { CoachChatView().backSwipe(goBack) }
                .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(3)
            NavigationStack { ProgressScreen().rcDestinations().backSwipe(goBack) }
                .tabItem { Label("Progrès", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(4)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .onChange(of: selection) { old, _ in
            if isGoingBack {
                isGoingBack = false
            } else {
                history.append(old)
                if history.count > 20 { history.removeFirst() }
            }
        }
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        // Ferme le clavier (message en cours au coach) avant de changer d'onglet.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isGoingBack = true
        selection = previous
    }
}

extension View {
    /// Glissement depuis le bord gauche vers la droite. Posé sur l'écran racine d'un onglet seulement :
    /// dans un écran ouvert depuis l'onglet, le retour natif d'iOS garde la main.
    func backSwipe(_ action: @escaping () -> Void) -> some View {
        simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
            if value.startLocation.x < 30, value.translation.width > 80, abs(value.translation.height) < 60 { action() }
        })
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
            if let run = runs.first(where: { !$0.isStrength }) { ReplayView(run: run, progress: 0.4, intro: nil) }
        case "replayplay":
            if let run = runs.first(where: { !$0.isStrength }) { ReplayView(run: run, progress: 0.4, intro: nil, isPlaying: true) }
        case "replaymap":
            if let run = runs.first(where: { !$0.isStrength }) { ReplayView(run: run, style: 2, progress: 0.4, intro: nil) }
        case "replayrelief":
            if let run = runs.first(where: { !$0.isStrength }) { ReplayView(run: run, style: 1, progress: 0.4, intro: nil) }
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
