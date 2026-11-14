import SwiftUI
import SwiftData
import RunCoachCore

/// Records personnels (étape 7, n° 6) : meilleurs 1, 5 et 10 km pris n'importe où dans une sortie, et plus longue
/// sortie. Toucher un record ouvre la sortie où il a été établi.
struct RecordsCard: View {
    let runs: [Run]

    var body: some View {
        let running = runs.filter(\.isRunning)
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Records")
            ForEach(PersonalRecords.distancesM, id: \.self) { d in
                if let run = running.filter({ $0.best(d) != nil }).min(by: { $0.best(d)! < $1.best(d)! }), let time = run.best(d) {
                    row("\(Int(d / 1000)) km", value: Fmt.duration(time),
                        detail: Fmt.pace(sPerKm: time / (d / 1000)) + " /km", run: run)
                }
            }
            if let longest = running.max(by: { $0.distanceM < $1.distanceM }), longest.distanceM > 0 {
                row("Plus longue", value: Fmt.km(longest.distanceM, decimals: 1) + " km",
                    detail: Fmt.duration(longest.durationS), run: longest)
            }
            if running.allSatisfy({ $0.bestsComputed != true }) {
                Text("Calcul des records à partir de tes sorties…")
                    .font(.footnote)
                    .foregroundStyle(Color.rc.textSecondary)
                    .redacted(reason: .placeholder)
            }
        }
        .rcCard()
    }

    private func row(_ label: String, value: String, detail: String, run: Run) -> some View {
        NavigationLink(value: run) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Color.rc.warning)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.rc.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.rcHeadline)
                        .monospacedDigit()
                        .foregroundStyle(Color.rc.textPrimary)
                    Text(detail + " · " + run.startDate.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.rc.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
