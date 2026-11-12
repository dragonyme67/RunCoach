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

/// Temps passé dans chacune des 5 zones de fréquence cardiaque : une barre par zone, de la plus intense à la plus douce.
struct ZoneBreakdown: View {
    /// Secondes passées dans chaque zone, 5 valeurs.
    let seconds: [Double]

    var body: some View {
        let total = max(1, seconds.reduce(0, +))
        let longest = max(1, seconds.max() ?? 1)
        let dominant = (seconds.firstIndex(of: longest) ?? 0) + 1
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Surtout en zone \(dominant) · \(Color.rc.zoneName(dominant))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.rc.textPrimary)
            ForEach(Array(seconds.enumerated()).reversed(), id: \.offset) { index, value in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.s) {
                        Text("Z\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.rc.textPrimary)
                        Text(Color.rc.zoneName(index + 1))
                            .font(.caption)
                            .foregroundStyle(Color.rc.textSecondary)
                        Spacer()
                        Text(Fmt.duration(value))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.rc.textPrimary)
                        Text("\(Int((value / total * 100).rounded())) %")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.rc.textSecondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.rc.surfaceRaised)
                            Capsule()
                                .fill(Color.rc.zone(index + 1))
                                .frame(width: value > 0 ? max(10, geo.size.width * value / longest) : 0)
                        }
                    }
                    .frame(height: 10)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Zone \(index + 1), \(Color.rc.zoneName(index + 1)), \(Fmt.duration(value)), \(Int((value / total * 100).rounded())) pour cent")
            }
        }
    }
}
