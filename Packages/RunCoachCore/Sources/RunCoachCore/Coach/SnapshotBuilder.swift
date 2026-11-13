import Foundation

/// Construit le résumé envoyé à l'IA (ARCHITECTURE.md §6.2) à partir des données locales.
/// Seuls des agrégats en sortent : ni prénom, ni lieu, ni coordonnée GPS.
public enum SnapshotBuilder {
    public struct Input: Sendable {
        public var today: Date
        public var birthDate: Date
        public var sex: String?
        public var runningSince: Date
        public var injuryNote: String
        public var currentPain: Bool
        public var fatigueLevel: String
        public var wantsStrength: Bool
        public var strengthEquipment: String
        /// Sortie saisie à l'onboarding (sa date est ignorée) et son ressenti `easy` / `moderate` / `hard`.
        public var onboardingRun: RunSummary
        public var onboardingEffort: String
        public var thresholdOverrideSPerKm: Double?
        public var hrMaxBpm: Double
        /// `race` ou `fitness`
        public var goalKind: String
        public var goalDistanceKm: Double?
        public var goalDate: Date?
        public var goalTargetS: Double?
        /// Sorties de course à pied (pas le renfo).
        public var runs: [RunSummary]
        public var recovery: AthleteSnapshot.Recovery
        public var missedLast14d: Int

        public init(today: Date, birthDate: Date, sex: String?, runningSince: Date, injuryNote: String, currentPain: Bool,
                    fatigueLevel: String, wantsStrength: Bool, strengthEquipment: String, onboardingRun: RunSummary,
                    onboardingEffort: String, thresholdOverrideSPerKm: Double?, hrMaxBpm: Double, goalKind: String,
                    goalDistanceKm: Double?, goalDate: Date?, goalTargetS: Double?, runs: [RunSummary],
                    recovery: AthleteSnapshot.Recovery, missedLast14d: Int) {
            self.today = today
            self.birthDate = birthDate
            self.sex = sex
            self.runningSince = runningSince
            self.injuryNote = injuryNote
            self.currentPain = currentPain
            self.fatigueLevel = fatigueLevel
            self.wantsStrength = wantsStrength
            self.strengthEquipment = strengthEquipment
            self.onboardingRun = onboardingRun
            self.onboardingEffort = onboardingEffort
            self.thresholdOverrideSPerKm = thresholdOverrideSPerKm
            self.hrMaxBpm = hrMaxBpm
            self.goalKind = goalKind
            self.goalDistanceKm = goalDistanceKm
            self.goalDate = goalDate
            self.goalTargetS = goalTargetS
            self.runs = runs
            self.recovery = recovery
            self.missedLast14d = missedLast14d
        }

        /// Court depuis moins de 6 mois.
        public var isBeginner: Bool {
            runningSince > (DayKey.calendar.date(byAdding: .month, value: -6, to: today) ?? today)
        }
    }

    /// Allure seuil : réglage manuel, sinon sortie de référence des 6 dernières semaines, sinon celle de l'onboarding.
    public static func thresholdSPerKm(_ input: Input) -> Double {
        if let override = input.thresholdOverrideSPerKm { return override }
        if let ref = PaceModel.referenceRun(input.runs, today: input.today) {
            return PaceModel.thresholdSPerKm(distanceM: ref.distanceM, durationS: ref.durationS, effort: ref.perceivedEffort)
        }
        let run = input.onboardingRun
        return PaceModel.thresholdSPerKm(distanceM: run.distanceM, durationS: run.durationS, effort: PaceModel.effort(input.onboardingEffort))
    }

    /// Semaines complètes (lundi à dimanche) avant la semaine en cours, de la plus ancienne à la plus récente,
    /// en partant de la première sortie connue : sans historique, aucune semaine (G2 ne s'applique pas).
    public static func lastWeeks(_ runs: [RunSummary], today: Date, count: Int = 6) -> [AthleteSnapshot.Week] {
        guard let first = runs.map(\.date).min() else { return [] }
        let current = DayKey.weekStart(today)
        return (1...count).reversed().compactMap { back in
            let start = DayKey.addDays(-7 * back, to: current)
            let end = DayKey.addDays(7, to: start)
            guard end > first else { return nil }
            let week = runs.filter { $0.date >= start && $0.date < end }
            return AthleteSnapshot.Week(
                weekStart: DayKey.key(start), km: round1(week.reduce(0) { $0 + $1.distanceM } / 1000), runs: week.count,
                load: week.reduce(0) { $0 + LoadModel.edwardsLoad($1) }.rounded(),
                longestKm: round1((week.map(\.distanceM).max() ?? 0) / 1000))
        }
    }

    /// V0 et L0 du `MacroPlanner` : moyenne et plus longue sortie des 3 dernières semaines complètes,
    /// à défaut `séances × distance de la sortie de l'onboarding`.
    public static func baseline(_ input: Input, sessionsPerWeek: Int) -> (v0Km: Double, l0Km: Double) {
        let weeks = lastWeeks(input.runs, today: input.today, count: 3)
        guard !weeks.isEmpty else {
            let km = input.onboardingRun.distanceM / 1000
            return (Double(sessionsPerWeek) * km, km)
        }
        return (weeks.reduce(0) { $0 + $1.km } / Double(weeks.count), weeks.map(\.longestKm).max() ?? 0)
    }

    public static func snapshot(_ input: Input) -> AthleteSnapshot {
        let today = input.today
        let threshold = thresholdSPerKm(input)
        var paces: [String: [Int]] = [:]
        for kind in [WorkoutKind.recovery, .easy, .long, .tempo, .intervals] {
            if let zone = PaceModel.zone(kind, thresholdSPerKm: threshold) { paces[kind.rawValue] = [zone.fastSPerKm, zone.slowSPerKm] }
        }
        let zones = (5...9).map { [Int((Double($0) / 10 * input.hrMaxBpm).rounded()), Int((Double($0 + 1) / 10 * input.hrMaxBpm).rounded())] }

        let calendar = DayKey.calendar
        let age = calendar.dateComponents([.year], from: input.birthDate, to: today).year ?? 0
        let weeksRunning = max(0, (calendar.dateComponents([.day], from: input.runningSince, to: today).day ?? 0) / 7)
        let athlete = AthleteSnapshot.Athlete(
            age: age, sex: input.sex, runningSinceWeeks: weeksRunning, level: input.isBeginner ? "beginner" : "intermediate",
            injuryNote: input.injuryNote, currentPain: input.currentPain, fatigueLevel: input.fatigueLevel,
            wantsStrength: input.wantsStrength, strengthEquipment: input.strengthEquipment)

        var goal = AthleteSnapshot.Goal(kind: input.goalKind)
        if input.goalKind == "race", let km = input.goalDistanceKm, let date = input.goalDate {
            goal.distanceKm = km
            goal.date = DayKey.key(date)
            let days = calendar.dateComponents([.day], from: DayKey.weekStart(today), to: DayKey.weekStart(date)).day ?? 0
            goal.weeksLeft = max(0, days / 7 + 1)
            let predicted = PaceModel.predictedRaceS(thresholdSPerKm: threshold, distanceKm: km)
            goal.predictedTime = Fmt.duration(predicted)
            if let target = input.goalTargetS {
                goal.targetTime = Fmt.duration(target)
                goal.targetPaceSPerKm = Int((target / km).rounded())
                goal.feasibility = PaceModel.feasibility(predictedS: predicted, targetS: target)
            }
        }

        let recent = input.runs.filter { $0.date <= today }.sorted { $0.date > $1.date }.prefix(10)
        let lastRuns = recent.map {
            AthleteSnapshot.LastRun(date: DayKey.key($0.date), km: round1($0.distanceM / 1000),
                                    paceSPerKm: Int(($0.durationS / max($0.distanceM / 1000, 0.01)).rounded()),
                                    avgHr: $0.avgHR, plannedKind: nil, effort: $0.perceivedEffort)
        }
        let load = LoadModel.load(input.runs, today: today)

        return AthleteSnapshot(
            today: DayKey.key(today), athlete: athlete, goal: goal, pacesSPerKm: paces, hrZonesBpm: zones,
            lastWeeks: lastWeeks(input.runs, today: today), lastRuns: Array(lastRuns),
            load: AthleteSnapshot.Load(acute: load.acute.rounded(), chronic: load.chronic.rounded(), ratio: load.ratio.map { ($0 * 100).rounded() / 100 }),
            recovery: input.recovery, missedLast14d: input.missedLast14d)
    }

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}
