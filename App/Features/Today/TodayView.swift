import SwiftUI
import SwiftData
import RunCoachCore

/// Écran d'accueil. Information principale : la séance du jour.
struct TodayView: View {
    @Query(sort: \PlannedWorkout.dayKey) private var workouts: [PlannedWorkout]
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @Query private var profiles: [AthleteProfile]
    @Query private var syncStates: [SyncState]
    @Environment(SyncEngine.self) private var sync
    @Environment(CoachService.self) private var coach
    @State private var showGarminLogin = false

    private var todayKey: String { DayKey.key(Date()) }

    private var todayWorkout: PlannedWorkout? {
        workouts.first { $0.dayKey == todayKey && $0.status != "cancelled" }
    }

    private var nextWorkout: PlannedWorkout? {
        workouts.first { $0.dayKey > todayKey && $0.status == "planned" }
    }

    var body: some View {
        let week = WeekSummary(date: Date(), workouts: workouts, runs: runs)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                if let message = sync.message {
                    syncBanner(message)
                }
                if let profile = profiles.first, profile.currentPain {
                    painBanner(profile)
                }
                if !sync.isConnected && runs.isEmpty && sync.phase != .needsLogin {
                    EmptyState(icon: "applewatch", title: "Connecte Garmin",
                               message: "Tes sorties arrivent ici automatiquement, avec leur tracé.",
                               actionTitle: "Connecter mon compte") { showGarminLogin = true }
                        .rcCard()
                }
                // La semaine d'abord, puis la séance du jour (demande de l'utilisateur, 2026-11-14).
                weekCard(week)
                if let workout = todayWorkout {
                    NavigationLink(value: workout) {
                        HeroWorkoutCard(workout: workout)
                    }
                    .buttonStyle(.plain)
                    WatchStateRow(state: workout.garminSyncState)
                } else {
                    restCard
                }
                if profiles.first?.currentPain == false {
                    NavigationLink(value: AppRoute.health) {
                        Label("Une gêne, une douleur, de la fatigue ? Signale-le", systemImage: "cross.case")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.rc.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.s)
                    }
                }
                if let run = runs.first {
                    SectionHeader(title: "Dernière activité")
                    NavigationLink(value: run) {
                        RunRow(run: run)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("run-row")
                }
            }
            .padding(Spacing.l)
        }
        // Tâche détachée : SwiftUI annule la tâche de `refreshable` quand l'écran se redessine pendant une longue synchro,
        // ce qui affichait « Hors ligne » à tort (constat sur l'iPhone, 2026-11-14).
        .refreshable { await Task<Void, Never> { _ = await sync.sync(background: false) }.value }
        .rcScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showGarminLogin) { GarminLoginView() }
        .sensoryFeedback(.warning, trigger: sync.message) { _, new in new != nil }
    }

    /// Pastille : la synchro en cours, une erreur, ou « À jour » si une synchro a déjà réussi.
    private var pillState: SyncPill.Status? {
        switch sync.phase {
        case .syncing: return .syncing
        case .offline: return .offline
        case .needsLogin, .failed: return .error
        case .idle: return syncStates.first?.lastGarminSyncAt == nil ? nil : .upToDate
        }
    }

    /// Session perdue : le bandeau rouvre la connexion. Autre erreur : le message seul.
    private func syncBanner(_ message: String) -> some View {
        Button {
            if sync.phase == .needsLogin { showGarminLogin = true }
        } label: {
            Label(message, systemImage: sync.phase == .offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(sync.phase == .offline ? Color.rc.textSecondary : Color.rc.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rcCard()
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR"))))
                    .rcLabel()
                Text("Aujourd'hui")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.rc.textPrimary)
            }
            Spacer()
            if let pillState {
                SyncPill(state: pillState)
            }
            // Réglages ouverts dans la pile : bouton retour et glissement natifs d'iOS.
            NavigationLink(value: AppRoute.settings) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.rc.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Réglages")
        }
    }

    /// Douleur déclarée : son niveau, ce que ça change, et de quoi la mettre à jour sans chercher dans les réglages.
    private func painBanner(_ profile: AthleteProfile) -> some View {
        let severe = profile.pain == "severe"
        return VStack(alignment: .leading, spacing: Spacing.m) {
            Label(severe ? "Douleur nette déclarée" : "Gêne légère déclarée", systemImage: "cross.case.fill")
                .font(.headline)
                .foregroundStyle(severe ? Color.rc.danger : Color.rc.warning)
            Text(severe
                 ? "Repos ou récupération courte seulement. Consulte un médecin ou un kiné avant de reprendre."
                 : "Plus de séance intense et volume réduit ; footings et renfo restent possibles. Consulte si elle persiste.")
                .font(.subheadline)
                .foregroundStyle(Color.rc.textSecondary)
            HStack(spacing: Spacing.s) {
                Button("Ça va mieux") {
                    withAnimation(.rcStandard) { profile.pain = "none" }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.rc.accent)
                .foregroundStyle(Color.rc.onAccent)
                Button(severe ? "C'est plus léger" : "Ça s'aggrave") {
                    withAnimation(.rcStandard) { profile.pain = severe ? "mild" : "severe" }
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
        }
        .rcCard()
    }

    private var restCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label(workouts.isEmpty ? "Pas encore de plan" : "Repos",
                  systemImage: workouts.isEmpty ? "calendar.badge.clock" : "moon.zzz.fill")
                .font(.rcTitle)
                .foregroundStyle(Color.rc.textPrimary)
            Text(workouts.isEmpty
                 ? "Le coach prépare ta semaine à partir de lundi, dans les limites de progression calculées pour toi."
                 : "Le repos fait partie de l'entraînement : c'est là que tu progresses.")
                .font(.subheadline)
                .foregroundStyle(Color.rc.textSecondary)
            if workouts.isEmpty {
                PrimaryButton(title: coach.isGenerating ? "Le coach prépare ta semaine…" : "Générer mon plan", icon: "sparkles") {
                    Task { await coach.generateNextWeek() }
                }
                .disabled(coach.isGenerating)
                if coach.isGenerating {
                    Text(coach.generationStatus ?? "Jusqu'à 2 à 3 minutes si le service d'IA est saturé ; sinon, plan de secours.")
                        .font(.footnote)
                        .foregroundStyle(Color.rc.textSecondary)
                }
            }
            if let notice = coach.notice {
                Text(notice)
                    .font(.subheadline)
                    .foregroundStyle(Color.rc.textSecondary)
            }
            if let next = nextWorkout {
                Text("Prochaine séance : \(next.title)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.rc.textPrimary)
            }
        }
        .rcCard(padding: Spacing.xl)
    }

    private func weekCard(_ week: WeekSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SectionHeader(title: "Cette semaine")
            HStack(spacing: Spacing.xl) {
                RingProgress(value: week.progress)
                    .frame(width: 84, height: 84)
                    .overlay {
                        Text("\(Int((week.progress * 100).rounded())) %")
                            .font(.rcStat)
                            .monospacedDigit()
                            .foregroundStyle(Color.rc.textPrimary)
                    }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(Fmt.decimal(week.doneKm, decimals: 1))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.rc.textPrimary)
                        Text("/ " + Fmt.decimal(week.plannedKm, decimals: 1) + " km")
                            .font(.headline)
                            .foregroundStyle(Color.rc.textSecondary)
                    }
                    Text("courus sur prévus")
                        .rcLabel()
                }
            }
            .accessibilityElement(children: .combine)
            WeekStrip(days: week.days)
        }
        .rcCard()
    }
}
