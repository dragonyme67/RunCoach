import Foundation

public enum WorkoutKind: String, Codable, CaseIterable, Sendable {
    case easy, long, tempo, intervals, recovery, strength, race

    public var label: String {
        switch self {
        case .easy: return "Footing"
        case .long: return "Sortie longue"
        case .tempo: return "Tempo"
        case .intervals: return "Fractionné"
        case .recovery: return "Récupération"
        case .strength: return "Renfo"
        case .race: return "Course"
        }
    }

    /// Séances « dures » : jamais deux jours de suite (garde-fou G5).
    public var isHard: Bool {
        switch self {
        case .tempo, .intervals, .long, .race: return true
        case .easy, .recovery, .strength: return false
        }
    }

    public var isRun: Bool { self != .strength }
}

public enum StepIntent: String, Codable, Sendable {
    case warmup, run, recover, rest, cooldown

    public var label: String {
        switch self {
        case .warmup: return "Échauffement"
        case .run: return "Course"
        case .recover: return "Récupération"
        case .rest: return "Repos"
        case .cooldown: return "Retour au calme"
        }
    }
}

public enum StepEnd: String, Codable, Sendable {
    case time
    case distance
    case lapButton = "lap_button"
}

public enum TargetType: String, Codable, Sendable {
    case none
    case pace
    case hrZone = "hr_zone"
}
