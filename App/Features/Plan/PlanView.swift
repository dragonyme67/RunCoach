import SwiftUI
import SwiftData
import RunCoachCore

/// Calendrier du plan. Information principale : la semaine en cours.
struct PlanView: View {
    @Query(sort: \PlannedWorkout.dayKey) private var workouts: [PlannedWorkout]
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @Query private var plans: [TrainingPlan]
    @State private var mode = 0

    private static let weekdayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
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
            }
            .padding(Spacing.l)
        }
        .rcScreenBackground()
        .navigationTitle("Plan")
    }

    // MARK: - Semaine

    private var weekView: some View {
        let week = WeekSummary(date: Date(), workouts: workouts, runs: runs)
        let phase = plans.first?.macroWeeks.first?.phase
        return VStack(alignment: .leading, spacing: Spacing.m) {
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

    var body: some View {
        let kind = workout.kindValue
        let spec = workout.spec
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HeroWorkoutCard(workout: workout)
                if kind.isRun {
                    WatchStateRow(state: workout.garminSyncState)
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
                        ForEach(Array(spec.exercises.enumerated()), id: \.offset) { _, exercise in
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
                                    .foregroundStyle(kind.color)
                            }
                        }
                    }
                    .rcCard()
                }
                PrimaryButton(title: "En parler au coach", icon: "bubble.left.and.bubble.right.fill") {}
            }
            .padding(Spacing.l)
        }
        .rcScreenBackground()
        .navigationTitle(kind.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func volume(_ exercise: StrengthExercise) -> String {
        if let reps = exercise.reps { return "\(exercise.sets) × \(reps)" }
        if let seconds = exercise.durationS { return "\(exercise.sets) × \(seconds) s" }
        return "\(exercise.sets) séries"
    }
}
