import SwiftUI
import SwiftData
import RunCoachCore

/// État d'envoi de la séance sur la montre.
struct WatchStateRow: View {
    let state: String
    /// Raison de l'échec, montrée dans le détail d'une séance (§5.5).
    var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(text, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
            if state == "failed", let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.rc.textSecondary)
            }
        }
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
