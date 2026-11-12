import SwiftUI
import RunCoachCore

/// Pastille icône + libellé du type de séance.
struct WorkoutBadge: View {
    let kind: WorkoutKind

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: kind.icon)
            Text(kind.label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(kind.color)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 6)
        .background(kind.color.opacity(0.16), in: Capsule())
    }
}

/// Aperçu d'une séance en barres proportionnelles à la durée de chaque étape.
struct StepBars: View {
    let segments: [WorkoutSegment]
    let color: Color

    var body: some View {
        let total = max(1, segments.reduce(0) { $0 + $1.seconds })
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(fill(for: segment))
                        .frame(
                            width: max(2, geo.size.width * segment.seconds / total - 2),
                            height: height(for: segment, in: geo.size.height)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: 36)
        .accessibilityHidden(true)
    }

    private func fill(for segment: WorkoutSegment) -> Color {
        switch segment.intent {
        case .run: return segment.isFast ? color : color.opacity(0.75)
        case .warmup, .cooldown: return color.opacity(0.4)
        case .recover, .rest: return Color.rc.separator
        }
    }

    private func height(for segment: WorkoutSegment, in full: CGFloat) -> CGFloat {
        switch segment.intent {
        case .run: return segment.isFast ? full : full * 0.65
        case .warmup, .cooldown: return full * 0.45
        case .recover, .rest: return full * 0.25
        }
    }
}

/// Carte de la séance du jour.
struct HeroWorkoutCard: View {
    let workout: PlannedWorkout

    var body: some View {
        let kind = workout.kindValue
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                WorkoutBadge(kind: kind)
                Spacer()
                if workout.status == "done" {
                    Label("Fait", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.rc.accentText)
                }
            }
            Text(workout.title)
                .font(.rcTitle)
                .foregroundStyle(Color.rc.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
                HeroNumber(value: "\(workout.estimatedDurationMin)", unit: "min")
                if let km = workout.estimatedDistanceKm {
                    Text("≈ " + Fmt.decimal(km, decimals: 1) + " km")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.rc.textSecondary)
                }
            }
            if let spec = workout.spec, !spec.blocks.isEmpty {
                StepBars(segments: spec.segments(easyPaceSPerKm: 430), color: kind.color)
            }
            Text(workout.rationale)
                .font(.subheadline)
                .foregroundStyle(Color.rc.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .rcCard(padding: Spacing.xl)
        .overlay(alignment: .topLeading) {
            // Liseré de la couleur du type : la couleur n'est jamais seule, la pastille porte le libellé.
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(kind.color.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Ligne d'étape de séance : durée ou distance, cible, note.
struct StepRow: View {
    let step: WorkoutStep
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            RoundedRectangle(cornerRadius: 2)
                .fill(step.intent == .run ? color : Color.rc.separator)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(step.intent.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.rc.textPrimary)
                    Spacer()
                    Text(step.lengthLabel)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.rc.textPrimary)
                }
                if let target = step.target.label {
                    Text(target)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(color)
                }
                if let note = step.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Color.rc.textSecondary)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
