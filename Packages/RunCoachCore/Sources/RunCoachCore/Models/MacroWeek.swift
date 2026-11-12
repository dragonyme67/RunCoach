import Foundation

public enum TrainingPhase: String, Codable, Sendable {
    case base, build, peak, taper, race

    public var label: String {
        switch self {
        case .base: return "Fondation"
        case .build: return "Développement"
        case .peak: return "Pic"
        case .taper: return "Affûtage"
        case .race: return "Course"
        }
    }
}

public struct MacroWeek: Codable, Equatable, Sendable {
    public var weekStart: String
    public var phase: TrainingPhase
    public var targetKm: Double
    public var longRunKm: Double
    public var sessions: Int
    public var qualitySessions: Int
    public var isCutback: Bool

    public init(weekStart: String, phase: TrainingPhase, targetKm: Double, longRunKm: Double,
                sessions: Int, qualitySessions: Int, isCutback: Bool) {
        self.weekStart = weekStart
        self.phase = phase
        self.targetKm = targetKm
        self.longRunKm = longRunKm
        self.sessions = sessions
        self.qualitySessions = qualitySessions
        self.isCutback = isCutback
    }
}
