import SwiftUI
import RunCoachCore

/// Les 7 jours de la semaine : prévu (contour), fait (plein), manqué (barré), aujourd'hui (anneau accent).
struct WeekStrip: View {
    let days: [WeekSummary.Day]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: Spacing.s) {
                    Text(day.letter)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(day.isToday ? Color.rc.textPrimary : Color.rc.textSecondary)
                    dot(for: day)
                        .frame(width: 28, height: 28)
                        .overlay {
                            if day.isToday {
                                Circle().strokeBorder(Color.rc.accent, lineWidth: 2).padding(-5)
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(for: day))
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private func dot(for day: WeekSummary.Day) -> some View {
        if let kind = day.kind {
            switch day.status {
            case "done":
                Circle().fill(kind.color)
                    .overlay(Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(Color.rc.onAccent))
            case "missed", "skipped":
                Circle().strokeBorder(Color.rc.separator, lineWidth: 2)
                    .overlay(Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(Color.rc.textSecondary))
            default:
                Circle().strokeBorder(kind.color, lineWidth: 2)
                    .overlay(Image(systemName: kind.icon).font(.caption2).foregroundStyle(kind.color))
            }
        } else {
            Circle().fill(Color.rc.surfaceRaised).padding(9)
        }
    }

    private func label(for day: WeekSummary.Day) -> String {
        guard let kind = day.kind else { return "\(day.letter), repos" }
        switch day.status {
        case "done": return "\(day.letter), \(kind.label), fait"
        case "missed", "skipped": return "\(day.letter), \(kind.label), manqué"
        default: return "\(day.letter), \(kind.label), prévu"
        }
    }
}

/// Anneau de progression (volume de la semaine).
struct RingProgress: View {
    let value: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(Color.rc.surfaceRaised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, value)))
                .stroke(Color.rc.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.rcStandard, value: value)
        }
        .accessibilityHidden(true)
    }
}

/// Barre horizontale empilée des 5 zones de fréquence cardiaque.
struct ZoneBar: View {
    /// Secondes passées dans chaque zone, 5 valeurs.
    let seconds: [Double]

    var body: some View {
        let total = max(1, seconds.reduce(0, +))
        VStack(alignment: .leading, spacing: Spacing.s) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(seconds.enumerated()), id: \.offset) { index, value in
                        if value > 0 {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.rc.zone(index + 1))
                                .frame(width: max(3, geo.size.width * value / total - 2))
                        }
                    }
                }
            }
            .frame(height: 14)
            HStack(spacing: Spacing.m) {
                ForEach(Array(seconds.enumerated()), id: \.offset) { index, value in
                    HStack(spacing: 3) {
                        Circle().fill(Color.rc.zone(index + 1)).frame(width: 7, height: 7)
                        Text("Z\(index + 1) \(Int((value / total * 100).rounded())) %")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Color.rc.textSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Répartition du temps par zone de fréquence cardiaque")
    }
}
