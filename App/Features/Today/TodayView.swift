import SwiftUI
import SwiftData
import RunCoachCore

/// Écran d'accueil. Information principale : la séance du jour.
struct TodayView: View {
    @Query(sort: \PlannedWorkout.dayKey) private var workouts: [PlannedWorkout]
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @Query private var profiles: [AthleteProfile]
    @State private var showSettings = false

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
                if profiles.first?.currentPain == true {
                    painBanner
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
                    SectionHeader(title: "Dernière sortie")
                    NavigationLink(value: run) {
                        RunRow(run: run)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("run-row")
                }
            }
            .padding(Spacing.l)
        }
        .rcScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
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
            SyncPill(state: .upToDate)
            Button {
                showSettings = true
            } label: {
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
            Label("Repos", systemImage: "moon.zzz.fill")
                .font(.rcTitle)
                .foregroundStyle(Color.rc.textPrimary)
            Text("Le repos fait partie de l'entraînement : c'est là que tu progresses.")
                .font(.subheadline)
                .foregroundStyle(Color.rc.textSecondary)
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
            Image(systemName: "figure.run")
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
                Text(Fmt.km(run.distanceM) + " km")
                    .font(.rcStat)
                    .monospacedDigit()
                    .foregroundStyle(Color.rc.textPrimary)
                Text(Fmt.pace(sPerKm: run.paceSPerKm) + " /km")
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
