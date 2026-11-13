import Foundation

/// Cahier des charges d'une semaine, calculé par le code et imposé à l'IA (ARCHITECTURE.md §6.2).
public struct WeekBrief: Codable, Equatable, Sendable {
    public var weekStart: String
    public var phase: TrainingPhase
    public var isCutback: Bool
    public var targetKm: Double
    public var minKm: Double
    public var maxKm: Double
    public var runSessions: Int
    public var maxQualitySessions: Int
    /// Fourchette [min, max] de la sortie longue, en km.
    public var longRunKm: [Double]
    public var longRunDay: String?
    public var availableDays: [String]
    public var maxSessionMin: Int
    public var strengthSessions: Int
    public var strengthDays: [String]
    public var allowedKinds: [WorkoutKind]
    public var notes: [String]

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start", phase, isCutback = "is_cutback"
        case targetKm = "target_km", minKm = "min_km", maxKm = "max_km"
        case runSessions = "run_sessions", maxQualitySessions = "max_quality_sessions"
        case longRunKm = "long_run_km", longRunDay = "long_run_day", availableDays = "available_days"
        case maxSessionMin = "max_session_min", strengthSessions = "strength_sessions", strengthDays = "strength_days"
        case allowedKinds = "allowed_kinds", notes
    }

    public init(weekStart: String, phase: TrainingPhase, isCutback: Bool, targetKm: Double, minKm: Double, maxKm: Double,
                runSessions: Int, maxQualitySessions: Int, longRunKm: [Double], longRunDay: String?,
                availableDays: [String], maxSessionMin: Int, strengthSessions: Int, strengthDays: [String],
                allowedKinds: [WorkoutKind], notes: [String] = []) {
        self.weekStart = weekStart
        self.phase = phase
        self.isCutback = isCutback
        self.targetKm = targetKm
        self.minKm = minKm
        self.maxKm = maxKm
        self.runSessions = runSessions
        self.maxQualitySessions = maxQualitySessions
        self.longRunKm = longRunKm
        self.longRunDay = longRunDay
        self.availableDays = availableDays
        self.maxSessionMin = maxSessionMin
        self.strengthSessions = strengthSessions
        self.strengthDays = strengthDays
        self.allowedKinds = allowedKinds
        self.notes = notes
    }
}
