import SwiftUI
import SwiftData
import RunCoachCore

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
