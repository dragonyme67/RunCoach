import Foundation

public struct WorkoutTarget: Codable, Equatable, Sendable {
    public var type: TargetType
    /// Borne rapide, en secondes par km.
    public var minSPerKm: Int?
    /// Borne lente, en secondes par km.
    public var maxSPerKm: Int?
    public var hrZone: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case minSPerKm = "min_s_per_km"
        case maxSPerKm = "max_s_per_km"
        case hrZone = "hr_zone"
    }

    public init(type: TargetType, minSPerKm: Int? = nil, maxSPerKm: Int? = nil, hrZone: Int? = nil) {
        self.type = type
        self.minSPerKm = minSPerKm
        self.maxSPerKm = maxSPerKm
        self.hrZone = hrZone
    }

    public static let none = WorkoutTarget(type: .none)

    public static func pace(_ minSPerKm: Int, _ maxSPerKm: Int) -> WorkoutTarget {
        WorkoutTarget(type: .pace, minSPerKm: minSPerKm, maxSPerKm: maxSPerKm)
    }

    /// « 5:25–5:40 /km », « Zone 2 », ou nil sans cible.
    public var label: String? {
        switch type {
        case .none:
            return nil
        case .pace:
            guard let lo = minSPerKm, let hi = maxSPerKm else { return nil }
            return Fmt.pace(sPerKm: Double(lo)) + "–" + Fmt.pace(sPerKm: Double(hi)) + " /km"
        case .hrZone:
            guard let zone = hrZone else { return nil }
            return "Zone \(zone)"
        }
    }
}

public struct WorkoutStep: Codable, Equatable, Sendable {
    public var intent: StepIntent
    public var end: StepEnd
    /// Secondes si `end == .time`, mètres si `end == .distance`, nil pour le bouton Lap.
    public var value: Double?
    public var target: WorkoutTarget
    public var note: String?

    public init(intent: StepIntent, end: StepEnd, value: Double?, target: WorkoutTarget = .none, note: String? = nil) {
        self.intent = intent
        self.end = end
        self.value = value
        self.target = target
        self.note = note
    }

    /// Durée estimée : les étapes en distance sont converties avec l'allure cible, sinon l'allure facile.
    public func estimatedSeconds(easyPaceSPerKm: Double) -> Double {
        switch end {
        case .time:
            return value ?? 0
        case .distance:
            var pace = easyPaceSPerKm
            if target.type == .pace, let lo = target.minSPerKm, let hi = target.maxSPerKm {
                pace = Double(lo + hi) / 2
            }
            return (value ?? 0) / 1000 * pace
        case .lapButton:
            return 60
        }
    }

    /// « 10 min », « 400 m », « Bouton Lap ».
    public var lengthLabel: String {
        switch end {
        case .time:
            return Fmt.minutes(value ?? 0)
        case .distance:
            let meters = value ?? 0
            if meters >= 1000 { return Fmt.km(meters, decimals: 1) + " km" }
            return "\(Int(meters.rounded())) m"
        case .lapButton:
            return "Bouton Lap"
        }
    }
}

public struct WorkoutBlock: Codable, Equatable, Sendable {
    /// 1 = pas de répétition.
    public var repeatCount: Int
    public var steps: [WorkoutStep]

    enum CodingKeys: String, CodingKey {
        case repeatCount = "repeat"
        case steps
    }

    public init(repeatCount: Int = 1, steps: [WorkoutStep]) {
        self.repeatCount = repeatCount
        self.steps = steps
    }
}

public struct StrengthExercise: Codable, Equatable, Sendable {
    public var exerciseId: String
    public var sets: Int
    public var reps: Int?
    public var durationS: Int?
    public var restS: Int
    public var note: String?

    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case sets
        case reps
        case durationS = "duration_s"
        case restS = "rest_s"
        case note
    }

    public init(exerciseId: String, sets: Int, reps: Int? = nil, durationS: Int? = nil, restS: Int, note: String? = nil) {
        self.exerciseId = exerciseId
        self.sets = sets
        self.reps = reps
        self.durationS = durationS
        self.restS = restS
        self.note = note
    }
}

/// Une étape déroulée (répétitions à plat) avec sa durée estimée, pour l'aperçu en barres.
public struct WorkoutSegment: Equatable, Sendable {
    public let intent: StepIntent
    public let seconds: Double
    public let isFast: Bool
}

public struct WorkoutSpec: Codable, Equatable, Sendable {
    public var date: String
    public var kind: WorkoutKind
    public var title: String
    public var rationale: String
    public var estimatedDurationMin: Int
    public var estimatedDistanceKm: Double?
    public var blocks: [WorkoutBlock]
    public var exercises: [StrengthExercise]

    enum CodingKeys: String, CodingKey {
        case date, kind, title, rationale
        case estimatedDurationMin = "estimated_duration_min"
        case estimatedDistanceKm = "estimated_distance_km"
        case blocks, exercises
    }

    public init(date: String, kind: WorkoutKind, title: String, rationale: String,
                estimatedDurationMin: Int, estimatedDistanceKm: Double?,
                blocks: [WorkoutBlock] = [], exercises: [StrengthExercise] = []) {
        self.date = date
        self.kind = kind
        self.title = title
        self.rationale = rationale
        self.estimatedDurationMin = estimatedDurationMin
        self.estimatedDistanceKm = estimatedDistanceKm
        self.blocks = blocks
        self.exercises = exercises
    }

    public func segments(easyPaceSPerKm: Double) -> [WorkoutSegment] {
        var out: [WorkoutSegment] = []
        for block in blocks {
            for _ in 0..<max(1, block.repeatCount) {
                for step in block.steps {
                    out.append(WorkoutSegment(
                        intent: step.intent,
                        seconds: step.estimatedSeconds(easyPaceSPerKm: easyPaceSPerKm),
                        isFast: step.intent == .run && block.repeatCount > 1
                    ))
                }
            }
        }
        return out
    }
}
