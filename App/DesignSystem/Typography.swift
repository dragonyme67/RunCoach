import SwiftUI

/// Police système uniquement, styles dynamiques (Dynamic Type). Jamais de taille fixe dans les vues.
extension Font {
    static let rcStat = Font.system(.title2, design: .rounded, weight: .semibold)
    static let rcTitle = Font.title2.weight(.bold)
    static let rcHeadline = Font.headline
    static let rcLabel = Font.caption.weight(.medium)
}

extension View {
    /// Libellé d'une stat : petit, majuscules, secondaire.
    func rcLabel() -> some View {
        self
            .font(.rcLabel)
            .textCase(.uppercase)
            .foregroundStyle(Color.rc.textSecondary)
    }
}

/// Le chiffre principal d'un écran, avec son unité. Grossit avec Dynamic Type.
struct HeroNumber: View {
    let value: String
    var unit: String = ""
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 60

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.rc.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if !unit.isEmpty {
                Text(unit)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.rc.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
