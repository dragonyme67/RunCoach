import SwiftUI
import SwiftData
import RunCoachCore

/// Sélection des jours de la semaine (1 = lundi … 7 = dimanche).
struct WeekdayPicker: View {
    @Binding var selection: [Int]

    static let names = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
    private static let letters = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(1...7, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn {
                        selection.removeAll { $0 == day }
                    } else {
                        selection = (selection + [day]).sorted()
                    }
                } label: {
                    Text(WeekdayPicker.letters[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? Color.rc.onAccent : Color.rc.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? Color.rc.accent : Color.rc.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(WeekdayPicker.names[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
