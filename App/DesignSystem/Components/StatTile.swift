import SwiftUI

/// Tuile de stat : libellé, gros chiffre, unité.
struct StatTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                if let icon = icon {
                    Image(systemName: icon).font(.caption)
                }
                Text(label)
            }
            .rcLabel()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.rcStat)
                    .monospacedDigit()
                    .foregroundStyle(Color.rc.textPrimary)
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(Color.rc.textSecondary)
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rc.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value) \(unit)")
    }
}
