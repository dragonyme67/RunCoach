import Foundation

/// Une sortie avec ce qu'il faut pour l'analyser en détail.
public struct AnalyzedRun: Sendable {
    public var summary: RunSummary
    public var track: Track?
    public var avgCadenceSpm: Double?
    public var elevationGainM: Double?

    public init(summary: RunSummary, track: Track? = nil, avgCadenceSpm: Double? = nil, elevationGainM: Double? = nil) {
        self.summary = summary
        self.track = track
        self.avgCadenceSpm = avgCadenceSpm
        self.elevationGainM = elevationGainM
    }
}

/// Bilan de forme sur les 6 dernières semaines, calculé par le code et envoyé à l'IA dans `AthleteSnapshot.analysis`
/// (demande de l'utilisateur du 2026-11-13 : un bilan précis, points forts et points faibles).
/// « Récent » = les 3 dernières semaines, « avant » = les 3 précédentes.
public struct FitnessAnalysis: Codable, Equatable, Sendable {
    public struct Intensity: Codable, Equatable, Sendable {
        /// % du temps en zones FC 1–2, 3, 4–5.
        public var easyPct: Int
        public var moderatePct: Int
        public var hardPct: Int

        enum CodingKeys: String, CodingKey {
            case easyPct = "easy_pct", moderatePct = "moderate_pct", hardPct = "hard_pct"
        }
    }

    /// Semaines réellement couvertes (moins de 6 si l'historique est plus court).
    public var weeks: Int
    public var runs: Int
    public var runsPerWeek: Double
    public var intensity: Intensity?
    /// Sorties dont l'allure moyenne est plus rapide que l'allure facile mais plus lente que l'allure tempo.
    public var greyZoneRuns: Int
    /// Mètres parcourus par battement de cœur (distance / (minutes × FC moyenne)) : plus haut = plus économique.
    public var efficiencyRecent: Double?
    public var efficiencyBefore: Double?
    public var efficiencyChangePct: Double?
    /// Dérive cardiaque moyenne des sorties de 40 min ou plus : perte d'efficacité entre la 1re et la 2e moitié
    /// (hors 10 premières minutes). Sous 5 %, l'endurance de base tient.
    public var cardiacDriftPct: Double?
    public var driftRuns: Int
    /// Sorties de 3 km ou plus dont la 2e moitié est plus de 2 % plus lente que la 1re.
    public var positiveSplitRuns: Int
    public var splitRuns: Int
    /// Variation moyenne de l'allure d'un km à l'autre, en % (écart type / moyenne).
    public var kmPaceVariationPct: Double?
    public var cadenceSpm: Double?
    public var elevationGainMPerWeek: Double?
    public var longestRecentKm: Double
    public var longestBeforeKm: Double
    public var fastestKmSPerKm: Int?

    enum CodingKeys: String, CodingKey {
        case weeks, runs, runsPerWeek = "runs_per_week", intensity, greyZoneRuns = "grey_zone_runs"
        case efficiencyRecent = "efficiency_m_per_beat_recent", efficiencyBefore = "efficiency_m_per_beat_before"
        case efficiencyChangePct = "efficiency_change_pct", cardiacDriftPct = "cardiac_drift_pct", driftRuns = "drift_runs"
        case positiveSplitRuns = "positive_split_runs", splitRuns = "split_runs", kmPaceVariationPct = "km_pace_variation_pct"
        case cadenceSpm = "cadence_spm", elevationGainMPerWeek = "elevation_gain_m_per_week"
        case longestRecentKm = "longest_recent_km", longestBeforeKm = "longest_before_km", fastestKmSPerKm = "fastest_km_s_per_km"
    }
}

public enum FitnessAnalyzer {
    /// nil sans aucune sortie sur les 6 dernières semaines.
    public static func analyze(_ runs: [AnalyzedRun], today: Date, easy: PaceRange?, tempo: PaceRange?) -> FitnessAnalysis? {
        let end = DayKey.addDays(1, to: DayKey.calendar.startOfDay(for: today))
        let start = DayKey.addDays(-42, to: end)
        let split = DayKey.addDays(-21, to: end)
        let window = runs.filter { $0.summary.date >= start && $0.summary.date < end && $0.summary.distanceM > 0 && $0.summary.durationS > 0 }
        guard let first = window.map(\.summary.date).min() else { return nil }
        let days = DayKey.calendar.dateComponents([.day], from: first, to: end).day ?? 42
        let weeks = min(6, max(1, Int((Double(days) / 7).rounded(.up))))
        let recent = window.filter { $0.summary.date >= split }
        let before = window.filter { $0.summary.date < split }

        var intensity: FitnessAnalysis.Intensity?
        let zones = window.map(\.summary.hrZoneSeconds).filter { $0.count == 5 }
        let zoneTotals = (0..<5).map { i in zones.reduce(0) { $0 + $1[i] } }
        let zoneSum = zoneTotals.reduce(0, +)
        if zoneSum > 0 {
            func pct(_ s: Double) -> Int { Int((s / zoneSum * 100).rounded()) }
            intensity = .init(easyPct: pct(zoneTotals[0] + zoneTotals[1]), moderatePct: pct(zoneTotals[2]),
                              hardPct: pct(zoneTotals[3] + zoneTotals[4]))
        }

        var grey = 0
        if let easy, let tempo {
            for run in window {
                let pace = run.summary.durationS / (run.summary.distanceM / 1000)
                if pace < Double(easy.fastSPerKm - 5), pace > Double(tempo.slowSPerKm + 5) { grey += 1 }
            }
        }

        func efficiency(_ runs: [AnalyzedRun]) -> Double? {
            let values = runs.compactMap { run -> Double? in
                guard let hr = run.summary.avgHR, hr > 0 else { return nil }
                return run.summary.distanceM / (run.summary.durationS / 60 * Double(hr))
            }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let effRecent = efficiency(recent), effBefore = efficiency(before)
        var effChange: Double?
        if let r = effRecent, let b = effBefore, b > 0 { effChange = round1((r - b) / b * 100) }

        let drifts = window.compactMap { $0.track.flatMap(driftPct) }
        var positive = 0, splitRuns = 0
        var variations: [Double] = []
        var fastest: Double?
        for run in window {
            guard let track = run.track else { continue }
            let paces = track.kmSplits().filter { $0.distanceM >= 990 }.map { $0.durationS / ($0.distanceM / 1000) }
            if let best = paces.min() { fastest = min(fastest ?? best, best) }
            guard paces.count >= 3 else { continue }
            splitRuns += 1
            let half = paces.count / 2
            let firstHalf = paces.prefix(half).reduce(0, +) / Double(half)
            let secondHalf = paces.suffix(paces.count - half).reduce(0, +) / Double(paces.count - half)
            if secondHalf > firstHalf * 1.02 { positive += 1 }
            let mean = paces.reduce(0, +) / Double(paces.count)
            let variance = paces.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(paces.count)
            variations.append(variance.squareRoot() / mean * 100)
        }

        let cadences = window.compactMap(\.avgCadenceSpm).filter { $0 > 0 }
        let gains = window.compactMap(\.elevationGainM)
        func longest(_ runs: [AnalyzedRun]) -> Double { round1((runs.map(\.summary.distanceM).max() ?? 0) / 1000) }

        return FitnessAnalysis(
            weeks: weeks, runs: window.count, runsPerWeek: round1(Double(window.count) / Double(weeks)),
            intensity: intensity, greyZoneRuns: grey,
            efficiencyRecent: effRecent.map(round2), efficiencyBefore: effBefore.map(round2), efficiencyChangePct: effChange,
            cardiacDriftPct: drifts.isEmpty ? nil : round1(drifts.reduce(0, +) / Double(drifts.count)), driftRuns: drifts.count,
            positiveSplitRuns: positive, splitRuns: splitRuns,
            kmPaceVariationPct: variations.isEmpty ? nil : round1(variations.reduce(0, +) / Double(variations.count)),
            cadenceSpm: cadences.isEmpty ? nil : (cadences.reduce(0, +) / Double(cadences.count)).rounded(),
            elevationGainMPerWeek: gains.isEmpty ? nil : (gains.reduce(0, +) / Double(weeks)).rounded(),
            longestRecentKm: longest(recent), longestBeforeKm: longest(before),
            fastestKmSPerKm: fastest.map { Int($0.rounded()) })
    }

    /// Dérive cardiaque d'une sortie de 40 min ou plus, en % ; nil sans FC ni vitesse.
    /// Arrêts (moins de 1,5 m/s) et 10 premières minutes exclus.
    static func driftPct(_ track: Track) -> Double? {
        guard let hr = track.hr, let speed = track.speed, let total = track.t.last, total >= 2400 else { return nil }
        let middle = (600 + total) / 2
        var first = (speed: 0.0, hr: 0.0), second = (speed: 0.0, hr: 0.0)
        for i in 0..<min(hr.count, speed.count, track.t.count) where track.t[i] >= 600 && speed[i] > 1.5 && hr[i] > 60 {
            if track.t[i] < middle {
                first.speed += speed[i]; first.hr += hr[i]
            } else {
                second.speed += speed[i]; second.hr += hr[i]
            }
        }
        guard first.hr > 0, second.hr > 0, first.speed > 0 else { return nil }
        // Rapport des sommes = rapport des moyennes : même nombre de relevés au numérateur et au dénominateur.
        let e1 = first.speed / first.hr, e2 = second.speed / second.hr
        return (e1 - e2) / e1 * 100
    }

    private static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}
