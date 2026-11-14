import SwiftUI
import SwiftData
import Charts
import RunCoachCore

/// Progression. Information principale : la distance à l'objectif.
/// (Nommé `ProgressScreen` : `ProgressView` est pris par SwiftUI.)
struct ProgressScreen: View {
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @Query private var goals: [Goal]
    @Environment(CoachService.self) private var coach
    @State private var analysis: FitnessAnalysis?

    var body: some View {
        let weeks = WeekVolume.last(12, runs: runs)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let goal = goals.first(where: { $0.isActive }) {
                    GoalCard(goal: goal, runs: runs)
                }
                if let analysis {
                    FitnessCard(analysis: analysis)
                }
                VStack(alignment: .leading, spacing: Spacing.m) {
                    SectionHeader(title: "Volume par semaine")
                    Chart(weeks) { week in
                        BarMark(x: .value("Semaine", week.start, unit: .weekOfYear), y: .value("km", week.km))
                            .foregroundStyle(Color.rc.accentText)
                            .cornerRadius(5)
                    }
                    .chartYAxisLabel("km")
                    .frame(height: 170)
                    .accessibilityLabel("Kilomètres courus par semaine sur 12 semaines")
                }
                .rcCard()
                VStack(alignment: .leading, spacing: Spacing.m) {
                    SectionHeader(title: "Allure moyenne")
                    Chart(weeks.filter { $0.paceSPerKm > 0 }) { week in
                        LineMark(x: .value("Semaine", week.start, unit: .weekOfYear), y: .value("Allure", week.paceSPerKm))
                            .foregroundStyle(Color.rc.accentText)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Semaine", week.start, unit: .weekOfYear), y: .value("Allure", week.paceSPerKm))
                            .foregroundStyle(Color.rc.accentText)
                    }
                    // Axe inversé : plus haut = plus rapide.
                    .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let seconds = value.as(Double.self) {
                                    Text(Fmt.pace(sPerKm: seconds))
                                }
                            }
                        }
                    }
                    .chartYAxisLabel("min/km")
                    .frame(height: 150)
                    .accessibilityLabel("Allure moyenne par semaine")
                }
                .rcCard()
                VStack(alignment: .leading, spacing: Spacing.m) {
                    SectionHeader(title: "Charge")
                    Chart(weeks) { week in
                        AreaMark(x: .value("Semaine", week.start, unit: .weekOfYear), y: .value("Charge", week.load))
                            .foregroundStyle(Color.rc.accentText.opacity(0.25))
                        LineMark(x: .value("Semaine", week.start, unit: .weekOfYear), y: .value("Charge", week.load))
                            .foregroundStyle(Color.rc.accentText)
                    }
                    .frame(height: 130)
                    .accessibilityLabel("Charge d'entraînement par semaine")
                }
                .rcCard()
                if recentZoneSeconds.contains(where: { $0 > 0 }) {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        SectionHeader(title: "Zones cardiaques · 4 semaines")
                        ZoneBreakdown(seconds: recentZoneSeconds)
                    }
                    .rcCard()
                }
            }
            .padding(Spacing.l)
        }
        .rcScreenBackground()
        .navigationTitle("Progrès")
        // Décode les tracés des 6 dernières semaines : une fois à l'ouverture, pas à chaque rendu.
        .task(id: runs.count) { analysis = coach.analysis() }
    }

    /// Temps cumulé par zone sur les 28 derniers jours.
    private var recentZoneSeconds: [Double] {
        let since = DayKey.addDays(-28, to: Date())
        var sum = [Double](repeating: 0, count: 5)
        for run in runs where run.startDate >= since && run.hrZoneSeconds.count == 5 {
            for i in 0..<5 { sum[i] += run.hrZoneSeconds[i] }
        }
        return sum
    }
}

/// Bilan de forme des 6 dernières semaines, calculé par l'app (`FitnessAnalyzer`) : les mêmes chiffres que reçoit le coach.
struct FitnessCard: View {
    let analysis: FitnessAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Bilan de forme · \(analysis.weeks) semaine\(analysis.weeks > 1 ? "s" : "")")
            row("Régularité", Fmt.decimal(analysis.runsPerWeek, decimals: 1) + " sortie(s) par semaine")
            if let i = analysis.intensity {
                row("Intensité", "\(i.easyPct) % facile · \(i.moderatePct) % modéré · \(i.hardPct) % dur", hint: "Repère : environ 80 % en facile.")
            }
            row("Zone grise", "\(analysis.greyZoneRuns) sortie(s) sur \(analysis.runs)",
                hint: "Plus vite que le footing, moins vite que le tempo : fatigue sans faire progresser.")
            if let e = analysis.efficiencyRecent {
                let change = analysis.efficiencyChangePct.map { " (" + ($0 >= 0 ? "+" : "") + Fmt.decimal($0, decimals: 1) + " %)" } ?? ""
                row("Efficacité", Fmt.decimal(e, decimals: 2) + " m par battement" + change,
                    hint: "Distance par battement de cœur, 3 dernières semaines contre les 3 d'avant.")
            }
            if let drift = analysis.cardiacDriftPct {
                row("Dérive cardiaque", Fmt.decimal(drift, decimals: 1) + " % sur \(analysis.driftRuns) sortie(s) de 40 min ou plus",
                    hint: "Sous 5 % : ton endurance de base tient sur la durée.")
            }
            if analysis.splitRuns > 0 {
                row("Gestion d'allure", "\(analysis.positiveSplitRuns) départ(s) trop rapide(s) sur \(analysis.splitRuns)"
                    + (analysis.kmPaceVariationPct.map { " · écart entre km " + Fmt.decimal($0, decimals: 1) + " %" } ?? ""))
            }
            if let cadence = analysis.cadenceSpm {
                row("Cadence", "\(Int(cadence)) pas/min")
            }
            if let gain = analysis.elevationGainMPerWeek {
                row("Dénivelé", "\(Int(gain)) m par semaine")
            }
            row("Plus longue sortie", Fmt.decimal(analysis.longestRecentKm, decimals: 1) + " km (avant : "
                + Fmt.decimal(analysis.longestBeforeKm, decimals: 1) + " km)")
            if let fastest = analysis.fastestKmSPerKm {
                row("Meilleur km", Fmt.pace(sPerKm: Double(fastest)) + " /km")
            }
            Text("Demande au coach de t'expliquer ce bilan : il reçoit ces chiffres.")
                .font(.caption)
                .foregroundStyle(Color.rc.textSecondary)
        }
        .rcCard()
    }

    private func row(_ label: String, _ value: String, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).rcLabel()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.rc.textPrimary)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(Color.rc.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Volume, allure et charge d'une semaine.
struct WeekVolume: Identifiable {
    let start: Date
    let km: Double
    let paceSPerKm: Double
    let load: Double
    var id: Date { start }

    static func last(_ count: Int, runs: [Run]) -> [WeekVolume] {
        let thisWeek = DayKey.weekStart(Date())
        var out: [WeekVolume] = []
        for i in stride(from: count - 1, through: 0, by: -1) {
            let start = DayKey.addDays(-7 * i, to: thisWeek)
            let end = DayKey.addDays(7, to: start)
            let weekRuns = runs.filter { $0.startDate >= start && $0.startDate < end }
            // Allure : seulement les activités avec distance, sinon la durée du renfo la fausse.
            let meters = weekRuns.reduce(0) { $0 + $1.distanceM }
            let seconds = weekRuns.filter { $0.distanceM > 0 }.reduce(0) { $0 + $1.durationS }
            let load = weekRuns.reduce(0) { $0 + ($1.edwardsLoad ?? 0) }
            out.append(WeekVolume(
                start: start,
                km: meters / 1000,
                paceSPerKm: meters > 0 ? seconds / (meters / 1000) : 0,
                load: load
            ))
        }
        return out
    }
}

struct GoalCard: View {
    let goal: Goal
    let runs: [Run]

    var body: some View {
        let daysLeft = goal.raceDate.map { DayKey.calendar.dateComponents([.day], from: Date(), to: $0).day ?? 0 }
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Label(goal.name, systemImage: "flag.checkered")
                    .font(.headline)
                    .foregroundStyle(Color.rc.textPrimary)
                Spacer()
                if let date = goal.raceDate {
                    Text(date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "fr_FR"))))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.rc.textSecondary)
                }
            }
            if let daysLeft = daysLeft {
                HeroNumber(value: "\(max(0, daysLeft))", unit: "jours")
            }
            HStack(spacing: Spacing.m) {
                if let target = goal.targetTimeS {
                    StatTile(label: "Objectif", value: Fmt.duration(target))
                }
                if let estimate = estimatedTimeS {
                    StatTile(label: "Estimé aujourd'hui", value: Fmt.duration(estimate))
                }
            }
            if let target = goal.targetTimeS, let estimate = estimatedTimeS {
                ProgressView(value: min(1, target / estimate))
                    .tint(Color.rc.accent)
                    .accessibilityLabel("Progression vers l'objectif")
            }
        }
        .rcCard(padding: Spacing.xl)
    }

    // shortcut: estimation grossière (formule de Riegel sur la sortie la plus rapide récente) ;
    // remplacée par `PaceModel` à l'étape 4.
    private var estimatedTimeS: Double? {
        guard let distance = goal.raceDistanceM,
              let best = runs.prefix(9).filter({ $0.distanceM >= 3000 }).min(by: { $0.paceSPerKm < $1.paceSPerKm })
        else { return nil }
        return best.durationS * pow(distance / best.distanceM, 1.06)
    }
}

/// Onglet Activités : liste chronologique de toutes les activités (course et renfo).
struct RunListView: View {
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.m) {
                if runs.isEmpty {
                    EmptyState(icon: "figure.run", title: "Aucune activité",
                               message: sync.phase == .syncing
                                   ? (sync.progress ?? "Import en cours…")
                                   : "Connecte Garmin dans Réglages, puis tire l'écran vers le bas pour synchroniser.")
                }
                ForEach(runs) { run in
                    NavigationLink(value: run) {
                        RunRow(run: run)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("run-row")
                }
            }
            .padding(Spacing.l)
        }
        .refreshable { await Task { await sync.sync(background: false) }.value }
        .rcScreenBackground()
        .navigationTitle("Activités")
    }
}
