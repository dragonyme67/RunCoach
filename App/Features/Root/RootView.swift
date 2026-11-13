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
/// Glisser depuis le bord gauche d'un écran d'onglet ramène à l'onglet précédent, la page suivant le doigt comme
/// dans Safari ; clavier ouvert : le même geste le ferme seulement (demandes de l'utilisateur, 2026-11-13).
struct MainTabs: View {
    @State private var selection = 0
    /// Onglets visités, du plus ancien au plus récent.
    @State private var history: [Int] = []
    @State private var isGoingBack = false
    /// Décalage de l'onglet pendant le glissement de retour.
    @State private var dragX: CGFloat = 0
    @State private var keyboardVisible = false

    var body: some View {
        GeometryReader { geo in
            TabView(selection: $selection) {
                tab(0, geo.size.width).tabItem { Label("Aujourd'hui", systemImage: "sun.max.fill") }.tag(0)
                tab(1, geo.size.width).tabItem { Label("Plan", systemImage: "calendar") }.tag(1)
                tab(2, geo.size.width).tabItem { Label("Activités", systemImage: "figure.run") }.tag(2)
                tab(3, geo.size.width).tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right.fill") }.tag(3)
                tab(4, geo.size.width).tabItem { Label("Progrès", systemImage: "chart.line.uptrend.xyaxis") }.tag(4)
            }
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
    }

    /// Un onglet : sa pile de navigation, et pendant le glissement l'onglet précédent dessous, comme une page web.
    private func tab(_ index: Int, _ width: CGFloat) -> some View {
        let dragging = index == selection && dragX > 0
        return ZStack {
            if dragging, let previous = history.last {
                NavigationStack { root(previous) }
                    .offset(x: (dragX - width) * 0.3)
                    .overlay(Color.black.opacity(0.12 * (1 - dragX / max(width, 1))).allowsHitTesting(false))
                    .allowsHitTesting(false)
            }
            NavigationStack {
                root(index).simultaneousGesture(backGesture(width))
            }
            .offset(x: index == selection ? dragX : 0)
            .shadow(color: .black.opacity(dragging ? 0.25 : 0), radius: 12)
        }
    }

    @ViewBuilder
    private func root(_ index: Int) -> some View {
        switch index {
        case 0: TodayView().rcDestinations()
        case 1: PlanView().rcDestinations()
        case 2: RunListView().rcDestinations()
        case 3: CoachChatView().rcDestinations()
        default: ProgressScreen().rcDestinations()
        }
    }

    /// Posé sur l'écran racine de l'onglet seulement : dans un écran ouvert depuis l'onglet, le retour natif d'iOS garde la main.
    private func backGesture(_ width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard value.startLocation.x < 30, !keyboardVisible, !history.isEmpty else { return }
                dragX = max(0, value.translation.width)
            }
            .onEnded { value in
                guard value.startLocation.x < 30 else { return }
                if keyboardVisible {
                    if value.translation.width > 40 { dismissKeyboard() }
                    return
                }
                guard !history.isEmpty else { return }
                if value.translation.width > width * 0.35 || value.predictedEndTranslation.width > width * 0.6 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragX = width
                    } completion: {
                        goBack()
                        dragX = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { dragX = 0 }
                }
            }
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        isGoingBack = true
        selection = previous
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Écrans ouverts par valeur dans une pile de navigation (Réglages et ses sous-écrans).
enum AppRoute: Hashable {
    case settings, goal, training, profile, health, ai, aiDiagnostic, garminDiagnostic
}

extension View {
    /// Destinations communes à toutes les piles de navigation.
    /// Dans une pile, tous les liens passent par une valeur : après un `NavigationLink { vue }`,
    /// un `NavigationLink(value:)` rouvrait l'écran précédent au lieu du détail (constat sur iPhone).
    func rcDestinations() -> some View {
        self
            .navigationDestination(for: PlannedWorkout.self) { PlannedWorkoutDetailView(workout: $0) }
            .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .settings: SettingsView()
                case .goal: GoalEditView()
                case .training: TrainingSettingsView()
                case .profile: ProfileEditView()
                case .health: HealthSettingsView()
                case .ai: AISettingsView()
                case .aiDiagnostic: AIDiagnosticView()
                case .garminDiagnostic: GarminDiagnosticView()
                }
            }
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
            NavigationStack { SettingsView().rcDestinations() }
        case "tabs":
            MainTabs()
        default:
            NavigationStack { TodayView().rcDestinations() }
        }
    }
}
