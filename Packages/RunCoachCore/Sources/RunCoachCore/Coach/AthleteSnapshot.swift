import Foundation

/// Résumé compact envoyé à l'IA (ARCHITECTURE.md §6.2) : agrégats seulement, jamais de GPS, de lieu ni d'identité.
public struct AthleteSnapshot: Codable, Equatable, Sendable {
    public struct Athlete: Codable, Equatable, Sendable {
        public var age: Int
        public var sex: String?
        public var runningSinceWeeks: Int
        /// `beginner` (court depuis moins de 6 mois) ou `intermediate`.
        public var level: String
        public var injuryNote: String
        public var currentPain: Bool
        /// `low` / `normal` / `high`
        public var fatigueLevel: String
        public var wantsStrength: Bool
        public var strengthEquipment: String

        enum CodingKeys: String, CodingKey {
            case age, sex, runningSinceWeeks = "running_since_weeks", level, injuryNote = "injury_note"
            case currentPain = "current_pain", fatigueLevel = "fatigue_level", wantsStrength = "wants_strength"
            case strengthEquipment = "strength_equipment"
        }

        public init(age: Int, sex: String?, runningSinceWeeks: Int, level: String, injuryNote: String, currentPain: Bool,
                    fatigueLevel: String, wantsStrength: Bool, strengthEquipment: String) {
            self.age = age
            self.sex = sex
            self.runningSinceWeeks = runningSinceWeeks
            self.level = level
            self.injuryNote = injuryNote
            self.currentPain = currentPain
            self.fatigueLevel = fatigueLevel
            self.wantsStrength = wantsStrength
            self.strengthEquipment = strengthEquipment
        }

        public var isBeginner: Bool { level == "beginner" }
    }

    public struct Goal: Codable, Equatable, Sendable {
        /// `race` ou `fitness`
        public var kind: String
        public var distanceKm: Double?
        public var date: String?
        public var targetTime: String?
        public var targetPaceSPerKm: Int?
        public var weeksLeft: Int?
        public var predictedTime: String?
        public var feasibility: Feasibility?

        enum CodingKeys: String, CodingKey {
            case kind, distanceKm = "distance_km", date, targetTime = "target_time"
            case targetPaceSPerKm = "target_pace_s_per_km", weeksLeft = "weeks_left"
            case predictedTime = "predicted_time", feasibility
        }

        public init(kind: String, distanceKm: Double? = nil, date: String? = nil, targetTime: String? = nil,
                    targetPaceSPerKm: Int? = nil, weeksLeft: Int? = nil, predictedTime: String? = nil,
                    feasibility: Feasibility? = nil) {
            self.kind = kind
            self.distanceKm = distanceKm
            self.date = date
            self.targetTime = targetTime
            self.targetPaceSPerKm = targetPaceSPerKm
            self.weeksLeft = weeksLeft
            self.predictedTime = predictedTime
            self.feasibility = feasibility
        }
    }

    public struct Week: Codable, Equatable, Sendable {
        public var weekStart: String
        public var km: Double
        public var runs: Int
        public var load: Double
        public var longestKm: Double

        enum CodingKeys: String, CodingKey {
            case weekStart = "week_start", km, runs, load, longestKm = "longest_km"
        }

        public init(weekStart: String, km: Double, runs: Int, load: Double, longestKm: Double) {
            self.weekStart = weekStart
            self.km = km
            self.runs = runs
            self.load = load
            self.longestKm = longestKm
        }
    }

    public struct LastRun: Codable, Equatable, Sendable {
        public var date: String
        public var km: Double
        public var paceSPerKm: Int
        public var avgHr: Int?
        public var plannedKind: WorkoutKind?
        public var effort: Int?

        enum CodingKeys: String, CodingKey {
            case date, km, paceSPerKm = "pace_s_per_km", avgHr = "avg_hr", plannedKind = "planned_kind", effort
        }

        public init(date: String, km: Double, paceSPerKm: Int, avgHr: Int?, plannedKind: WorkoutKind?, effort: Int?) {
            self.date = date
            self.km = km
            self.paceSPerKm = paceSPerKm
            self.avgHr = avgHr
            self.plannedKind = plannedKind
            self.effort = effort
        }
    }

    public struct Load: Codable, Equatable, Sendable {
        public var acute: Double
        public var chronic: Double
        public var ratio: Double?

        public init(acute: Double, chronic: Double, ratio: Double?) {
            self.acute = acute
            self.chronic = chronic
            self.ratio = ratio
        }
    }

    public struct Recovery: Codable, Equatable, Sendable {
        public var sleepHAvg7d: Double?
        public var hrvStatus: String?
        public var restingHr: Int?

        enum CodingKeys: String, CodingKey {
            case sleepHAvg7d = "sleep_h_avg_7d", hrvStatus = "hrv_status", restingHr = "resting_hr"
        }

        public init(sleepHAvg7d: Double?, hrvStatus: String?, restingHr: Int?) {
            self.sleepHAvg7d = sleepHAvg7d
            self.hrvStatus = hrvStatus
            self.restingHr = restingHr
        }
    }

    public var today: String
    public var athlete: Athlete
    public var goal: Goal
    /// Par `WorkoutKind` (`recovery`, `easy`, `long`, `tempo`, `intervals`) : [borne rapide, borne lente].
    public var pacesSPerKm: [String: [Int]]
    /// 5 zones, [bas, haut] en bpm.
    public var hrZonesBpm: [[Int]]
    /// 6 semaines au plus, de la plus ancienne à la plus récente.
    public var lastWeeks: [Week]
    /// 10 sorties au plus.
    public var lastRuns: [LastRun]
    public var load: Load
    public var recovery: Recovery
    public var missedLast14d: Int

    enum CodingKeys: String, CodingKey {
        case today, athlete, goal, pacesSPerKm = "paces_s_per_km", hrZonesBpm = "hr_zones_bpm"
        case lastWeeks = "last_weeks", lastRuns = "last_runs", load, recovery, missedLast14d = "missed_last_14d"
    }

    public init(today: String, athlete: Athlete, goal: Goal, pacesSPerKm: [String: [Int]], hrZonesBpm: [[Int]],
                lastWeeks: [Week], lastRuns: [LastRun], load: Load, recovery: Recovery, missedLast14d: Int) {
        self.today = today
        self.athlete = athlete
        self.goal = goal
        self.pacesSPerKm = pacesSPerKm
        self.hrZonesBpm = hrZonesBpm
        self.lastWeeks = lastWeeks
        self.lastRuns = lastRuns
        self.load = load
        self.recovery = recovery
        self.missedLast14d = missedLast14d
    }

    public func pace(_ kind: WorkoutKind) -> PaceRange? {
        guard let p = pacesSPerKm[kind.rawValue], p.count == 2 else { return nil }
        return PaceRange(fastSPerKm: p[0], slowSPerKm: p[1])
    }
}
