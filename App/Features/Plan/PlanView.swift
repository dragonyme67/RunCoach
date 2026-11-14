import SwiftUI
import SwiftData
import RunCoachCore

/// Calendrier du plan. Information principale : la semaine en cours.
struct PlanView: View {
    @Query(sort: \PlannedWorkout.dayKey) private var workouts: [PlannedWorkout]
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @Query private var plans: [TrainingPlan]
    @Query private var goals: [Goal]
    @Query private var profiles: [AthleteProfile]
    @Environment(SyncEngine.self) private var sync
    @State private var mode = 0
    /// Semaine affichée : 0 = la semaine en cours, -1 la précédente, +1 la suivante…
    @State private var weekOffset = 0

    private static let weekdayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                planHeader
                Picker("Affichage", selection: $mode) {
                    Text("Semaine").tag(0)
                    Text("Mois").tag(1)
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: mode)

                if mode == 0 {
                    weekView
                } else {
                    monthView
                }
                watchSection
            }
            .padding(Spacing.l)
        }
        .rcScreenBackground()
        .navigationTitle("Plan")
    }

    // MARK: - Montre

    /// Envoi manuel sur la montre (demande de l'utilisateur, 2026-11-14), en plus de l'envoi automatique.
    private var watchSection: some View {
        let todayKey = DayKey.key(Date())
        let lastKey = DayKey.key(DayKey.addDays(WatchSync.windowDays - 1, to: Date()))
        let upcoming = workouts.filter { $0.status == "planned" && $0.dayKey >= todayKey && $0.dayKey <= lastKey }
        let sent = upcoming.filter { $0.garminSyncState == "sent" }.count
        let status: String
        if !sync.isConnected {
            status = "Connecte ton compte Garmin dans Réglages pour envoyer tes séances."
        } else if sync.phase == .syncing {
            status = "Envoi en cours…"
        } else if let message = sync.message {
            status = message
        } else {
            status = "\(sent) sur \(upcoming.count) séances des 7 prochains jours sont sur ta montre."
        }
        return VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Montre")
            Text(status)
                .font(.subheadline)
                .foregroundStyle(Color.rc.textSecondary)
            PrimaryButton(title: "Envoyer sur la montre", icon: "applewatch.radiowaves.left.and.right") {
                Task { await sync.pushWorkouts(retryFailed: true) }
            }
            .disabled(!sync.isConnected || sync.phase == .syncing)
            Text("Les séances arrivent sur la montre à sa prochaine synchro avec Garmin Connect.")
                .font(.caption)
                .foregroundStyle(Color.rc.textSecondary)
        }
        .rcCard()
    }

    // MARK: - Objectif et réglages du plan

    /// L'objectif et ce qui façonne le plan, modifiables d'ici sans passer par les Réglages (demande de l'utilisateur, 2026-11-14).
    private var planHeader: some View {
        let goal = goals.first { $0.isActive }
        let profile = profiles.first
        return VStack(alignment: .leading, spacing: Spacing.m) {
            NavigationLink(value: AppRoute.goal) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Objectif").rcLabel()
                        Text(goal?.name ?? "Choisir un objectif")
                            .font(.headline)
                            .foregroundStyle(Color.rc.textPrimary)
                        if let goal, let line = goalLine(goal) {
                            Text(line)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Color.rc.textSecondary)
                        }
                    }
                    Spacer()
                    Text("Modifier")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.rc.accentText)
                }
            }
            .buttonStyle(.plain)
            Divider()
            HStack(spacing: Spacing.s) {
                NavigationLink(value: AppRoute.training) {
                    chip("calendar", profile.map { "\($0.availableWeekdays.count) jours / sem." } ?? "Jours")
                }
                NavigationLink(value: AppRoute.health) {
                    chip("cross.case", ["mild": "Gêne légère", "severe": "Douleur nette"][profile?.pain ?? "none"]
                         ?? (profile?.fatigueLevel == "high" ? "Fatigue élevée" : "En forme"))
                }
            }
            .buttonStyle(.plain)
        }
        .rcCard()
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.rc.textPrimary)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 36)
            .background(Color.rc.surfaceRaised, in: Capsule())
    }

    /// « 16 mai 2027 · dans 183 jours · objectif 2:00:00 »
    private func goalLine(_ goal: Goal) -> String? {
        guard goal.kind == "race", let date = goal.raceDate else { return nil }
        let days = DayKey.calendar.dateComponents([.day], from: DayKey.calendar.startOfDay(for: Date()), to: date).day ?? 0
        var parts = [date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR"))),
                     days >= 0 ? "dans \(days) jours" : "passée"]
        if let target = goal.targetTimeS { parts.append("objectif " + Fmt.duration(target)) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Semaine

    private var weekView: some View {
        let date = DayKey.addDays(7 * weekOffset, to: Date())
        let week = WeekSummary(date: date, workouts: workouts, runs: runs)
        let weekKey = DayKey.key(DayKey.weekStart(date))
        let phase = plans.first { $0.isActive }?.macroWeeks.first { $0.weekStart == weekKey }?.phase
        return VStack(alignment: .leading, spacing: Spacing.m) {
            weekSwitcher(start: DayKey.weekStart(date))
            HStack(alignment: .firstTextBaseline) {
                HeroNumber(value: Fmt.decimal(week.plannedKm, decimals: 1), unit: "km prévus")
                Spacer()
                if let phase = phase {
                    Text(phase.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.rc.textSecondary)
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, 6)
                        .background(Color.rc.surface, in: Capsule())
                }
            }
            ForEach(week.days) { day in
                dayRow(day)
            }
        }
    }

    /// « ‹ Semaine du 16 novembre › » ; toucher le titre ramène à la semaine en cours.
    private func weekSwitcher(start: Date) -> some View {
        HStack {
            Button {
                withAnimation(.rcStandard) { weekOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Semaine précédente")
            Spacer()
            Button {
                withAnimation(.rcStandard) { weekOffset = 0 }
            } label: {
                VStack(spacing: 2) {
                    Text(weekOffset == 0 ? "Cette semaine" : weekOffset == 1 ? "Semaine prochaine" : weekOffset == -1 ? "Semaine dernière" : "Semaine")
                        .font(.headline)
                        .foregroundStyle(Color.rc.textPrimary)
                    Text("du " + start.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR"))))
                        .font(.caption)
                        .foregroundStyle(Color.rc.textSecondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                withAnimation(.rcStandard) { weekOffset += 1 }
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Semaine suivante")
        }
        .font(.headline)
        .foregroundStyle(Color.rc.accentText)
        .sensoryFeedback(.selection, trigger: weekOffset)
    }

    @ViewBuilder
    private func dayRow(_ day: WeekSummary.Day) -> some View {
        let workout = workouts.first { $0.dayKey == day.id && $0.status != "cancelled" }
        HStack(spacing: Spacing.l) {
            VStack(spacing: 2) {
                Text(day.date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_FR"))))
                    .rcLabel()
                Text(day.date.formatted(.dateTime.day()))
                    .font(.rcStat)
                    .monospacedDigit()
                    .foregroundStyle(day.isToday ? Color.rc.accentText : Color.rc.textPrimary)
            }
            .frame(width: 48)
            if let workout = workout {
                NavigationLink(value: workout) {
                    PlannedRow(workout: workout)
                }
                .buttonStyle(.plain)
            } else if day.id >= DayKey.key(Date()), let cancelled = workouts.first(where: { $0.dayKey == day.id && $0.status == "cancelled" }) {
                // Séance annulée à venir : sa fiche permet de la rétablir.
                NavigationLink(value: cancelled) {
                    Text("Repos · \(cancelled.title) annulée")
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundStyle(Color.rc.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.m)
                }
                .buttonStyle(.plain)
            } else {
                Text("Repos")
                    .font(.subheadline)
                    .foregroundStyle(Color.rc.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.m)
            }
        }
    }

    // MARK: - Mois

    private var monthView: some View {
        let calendar = DayKey.calendar
        let today = Date()
        let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let gridStart = DayKey.weekStart(monthStart)
        let month = calendar.component(.month, from: today)
        let todayKey = DayKey.key(today)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            Text(today.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_FR"))).capitalized)
                .font(.rcTitle)
                .foregroundStyle(Color.rc.textPrimary)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(Self.weekdayLetters[index]).rcLabel()
                }
                ForEach(0..<42, id: \.self) { offset in
                    monthCell(date: DayKey.addDays(offset, to: gridStart), month: month, todayKey: todayKey)
                }
            }
            legend
        }
    }

    private func monthCell(date: Date, month: Int, todayKey: String) -> some View {
        let key = DayKey.key(date)
        let isToday = key == todayKey
        let inMonth = DayKey.calendar.component(.month, from: date) == month
        let workout = workouts.first { $0.dayKey == key && $0.status != "cancelled" }
        let dot: Color = workout.map { dotColor($0) } ?? Color.clear
        return VStack(spacing: 4) {
            Text(date.formatted(.dateTime.day()))
                .font(isToday ? Font.subheadline.weight(.bold) : Font.subheadline)
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.rc.accentText : Color.rc.textPrimary)
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color.rc.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(inMonth ? 1 : 0.35)
    }

    private func dotColor(_ workout: PlannedWorkout) -> Color {
        workout.status == "missed" ? Color.rc.separator : workout.kindValue.color
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: Spacing.s) {
            ForEach(WorkoutKind.allCases, id: \.self) { kind in
                HStack(spacing: Spacing.xs) {
                    Circle().fill(kind.color).frame(width: 8, height: 8)
                    Text(kind.label)
                        .font(.caption)
                        .foregroundStyle(Color.rc.textSecondary)
                }
            }
        }
        .padding(.top, Spacing.s)
    }
}

/// Ligne d'une séance planifiée dans la liste de la semaine.
struct PlannedRow: View {
    let workout: PlannedWorkout

    var body: some View {
        let kind = workout.kindValue
        HStack(spacing: Spacing.m) {
            Image(systemName: kind.icon)
                .font(.headline)
                .foregroundStyle(kind.color)
                .frame(width: 40, height: 40)
                .background(kind.color.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                    .font(.headline)
                    .foregroundStyle(Color.rc.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.rc.textSecondary)
            }
            Spacer()
            statusIcon
        }
        .rcCard(padding: Spacing.m)
        .opacity(workout.status == "missed" ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = ["\(workout.estimatedDurationMin) min"]
        if let km = workout.estimatedDistanceKm {
            parts.append(Fmt.decimal(km, decimals: 1) + " km")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch workout.status {
        case "done":
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.rc.accentText)
                .accessibilityLabel("Fait")
        case "missed", "skipped":
            Image(systemName: "xmark.circle").foregroundStyle(Color.rc.textSecondary)
                .accessibilityLabel("Manqué")
        default:
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.rc.textSecondary)
        }
    }
}

/// Détail d'une séance planifiée : étapes ou exercices, explication, état d'envoi.
struct PlannedWorkoutDetailView: View {
    let workout: PlannedWorkout
    @Environment(CoachService.self) private var coach
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCancel = false

    /// « ma séance du mardi 17 novembre (Footing facile) »
    private var reference: String {
        let day = DayKey.date(workout.dayKey)?.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR"))) ?? workout.dayKey
        return "ma séance du \(day) (\(workout.title))"
    }

    var body: some View {
        let kind = workout.kindValue
        let spec = workout.spec
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HeroWorkoutCard(workout: workout)
                if workout.status == "planned" {
                    WatchStateRow(state: workout.garminSyncState, error: workout.garminSyncError)
                }
                if let spec = spec, !spec.blocks.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: "Déroulé")
                        ForEach(Array(spec.blocks.enumerated()), id: \.offset) { _, block in
                            if block.repeatCount > 1 {
                                Text("\(block.repeatCount) fois")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(kind.color)
                                    .padding(.top, Spacing.xs)
                            }
                            ForEach(Array(block.steps.enumerated()), id: \.offset) { _, step in
                                StepRow(step: step, color: kind.color)
                                    .padding(.leading, block.repeatCount > 1 ? Spacing.m : 0)
                            }
                        }
                    }
                    .rcCard()
                }
                if let spec = spec, !spec.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        SectionHeader(title: "Exercices")
                        ExerciseList(exercises: spec.exercises, color: kind.color)
                    }
                    .rcCard()
                }
                if workout.status == "planned" {
                    PrimaryButton(title: "Modifier avec le coach", icon: "bubble.left.and.bubble.right.fill") {
                        coach.pendingDraft = "Pour \(reference) : "
                    }
                    Button("Annuler cette séance", role: .destructive) { confirmCancel = true }
                        .frame(maxWidth: .infinity)
                } else if workout.status == "cancelled", workout.dayKey >= DayKey.key(Date()) {
                    // Rétablie telle quelle, sans repasser par le coach ni les garde-fous : elle les avait déjà passés.
                    PrimaryButton(title: "Rétablir cette séance", icon: "arrow.uturn.backward") {
                        workout.status = "planned"
                        workout.garminSyncState = "notSent"
                        workout.updatedAt = Date()
                        Task { await sync.pushWorkouts() }
                    }
                }
            }
            .padding(Spacing.l)
        }
        .rcScreenBackground()
        .navigationTitle(kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Annuler \(reference) ?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Annuler la séance", role: .destructive) {
                workout.status = "cancelled"
                workout.updatedAt = Date()
                if workout.garminWorkoutId != nil { workout.garminSyncState = "needsUpdate" }
                Task { await sync.pushWorkouts() }
                dismiss()
            }
            Button("Garder la séance", role: .cancel) {}
        } message: {
            Text("Elle disparaît du plan. Pour la déplacer ou la remplacer, passe plutôt par le coach.")
        }
    }
}

/// Exercices d'une séance de renfo : nom, consigne, séries × répétitions.
/// Partagé par le détail d'une séance planifiée et le détail d'une activité de renfo.
struct ExerciseList: View {
    let exercises: [StrengthExercise]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(Array(exercises.enumerated()), id: \.offset) { _, exercise in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(StrengthNames.name(exercise.exerciseId))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.rc.textPrimary)
                        if let note = exercise.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(Color.rc.textSecondary)
                        }
                    }
                    Spacer()
                    Text(volume(exercise))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(color)
                }
            }
        }
    }

    private func volume(_ exercise: StrengthExercise) -> String {
        if let reps = exercise.reps { return "\(exercise.sets) × \(reps)" }
        if let seconds = exercise.durationS { return "\(exercise.sets) × \(seconds) s" }
        return "\(exercise.sets) séries"
    }
}
