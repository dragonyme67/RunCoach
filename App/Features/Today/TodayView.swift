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
                if profiles.first?.currentPain == true {
                    painBanner
                }
                if !sync.isConnected && runs.isEmpty && sync.phase != .needsLogin {
                    EmptyState(icon: "applewatch", title: "Connecte Garmin",
                               message: "Tes sorties arrivent ici automatiquement, avec leur tracé.",
                               actionTitle: "Connecter mon compte") { showGarminLogin = true }
                        .rcCard()
                }
                if let workout = todayWorkout {
                    NavigationLink(value: workout) {
                        HeroWorkoutCard(workout: workout)
                    }
                    .buttonStyle(.plain)
                    WatchStateRow(state: workout.garminSyncState)
                } else {
                    restCard
                }
                weekCard(week)
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
        .refreshable { await sync.sync(background: false) }
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

    private var painBanner: some View {
        Label("Douleur déclarée : plan allégé. Consulte si elle persiste.", systemImage: "cross.case.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.rc.danger)
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

/// État d'envoi de la séance sur la montre.
struct WatchStateRow: View {
    let state: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.s)
    }

    private var text: String {
        switch state {
        case "sent": return "Sur ta montre"
        case "failed": return "Échec de l'envoi sur la montre"
        case "needsUpdate": return "Mise à jour en attente"
        default: return "En attente d'envoi sur la montre"
        }
    }

    private var icon: String {
        switch state {
        case "sent": return "applewatch.radiowaves.left.and.right"
        case "failed": return "exclamationmark.triangle.fill"
        default: return "clock"
        }
    }

    private var color: Color {
        switch state {
        case "sent": return Color.rc.accentText
        case "failed": return Color.rc.danger
        default: return Color.rc.textSecondary
        }
    }
}

/// Ligne compacte d'une sortie : date, distance, allure, durée.
struct RunRow: View {
    let run: Run

    var body: some View {
        HStack(spacing: Spacing.l) {
            Image(systemName: run.isStrength ? "dumbbell.fill" : "figure.run")
                .font(.title3)
                .foregroundStyle(Color.rc.onAccent)
                .frame(width: 44, height: 44)
                .background(Color.rc.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(run.name)
                    .font(.headline)
                    .foregroundStyle(Color.rc.textPrimary)
                Text(run.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))
                    .font(.caption)
                    .foregroundStyle(Color.rc.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                // Sans distance (renfo) : la durée, puis la fréquence cardiaque moyenne.
                Text(run.distanceM > 0 ? Fmt.km(run.distanceM) + " km" : Fmt.duration(run.durationS))
                    .font(.rcStat)
                    .monospacedDigit()
                    .foregroundStyle(Color.rc.textPrimary)
                Text(run.distanceM > 0 ? Fmt.pace(sPerKm: run.paceSPerKm) + " /km" : (run.avgHR.map { "\($0) bpm" } ?? ""))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.rc.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rc.textSecondary)
        }
        .rcCard()
        .accessibilityElement(children: .combine)
    }
}
