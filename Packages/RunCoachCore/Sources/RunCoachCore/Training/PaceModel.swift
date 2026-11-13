import Foundation

/// Fourchette d'allure : borne rapide puis borne lente, en secondes par km.
public struct PaceRange: Codable, Equatable, Sendable {
    public var fastSPerKm: Int
    public var slowSPerKm: Int

    public init(fastSPerKm: Int, slowSPerKm: Int) {
        self.fastSPerKm = fastSPerKm
        self.slowSPerKm = slowSPerKm
    }
}

public enum Feasibility: String, Codable, Sendable {
    case onTrack = "on_track"
    case ambitious
    case veryAmbitious = "very_ambitious"
}

/// Une sortie réduite à ce qui sert aux calculs (ARCHITECTURE.md §6.3).
public struct RunSummary: Equatable, Sendable {
    public var date: Date
    public var distanceM: Double
    public var durationS: Double
    /// Ressenti 1 à 10, nil si non saisi.
    public var perceivedEffort: Int?
    /// Secondes passées dans les zones FC 1 à 5, vide si inconnu.
    public var hrZoneSeconds: [Double]
    public var avgHR: Int?

    public init(date: Date, distanceM: Double, durationS: Double, perceivedEffort: Int? = nil, hrZoneSeconds: [Double] = [],
                avgHR: Int? = nil) {
        self.date = date
        self.distanceM = distanceM
        self.durationS = durationS
        self.perceivedEffort = perceivedEffort
        self.hrZoneSeconds = hrZoneSeconds
        self.avgHR = avgHR
    }
}

/// Allure seuil et zones d'allure (ARCHITECTURE.md §6.3). Approximations assumées, recalculées chaque semaine.
public enum PaceModel {
    /// Sortie de référence : la plus rapide des 6 dernières semaines d'au moins 3 km ; nil s'il n'y en a pas.
    public static func referenceRun(_ runs: [RunSummary], today: Date) -> RunSummary? {
        let since = DayKey.addDays(-42, to: today)
        return runs
            .filter { $0.date >= since && $0.date <= today && $0.distanceM >= 3000 && $0.durationS > 0 }
            .min { $0.durationS / $0.distanceM < $1.durationS / $1.distanceM }
    }

    /// Ressenti de l'onboarding (`easy` / `moderate` / `hard`) ramené sur l'échelle 1 à 10.
    public static func effort(_ onboarding: String) -> Int? {
        ["easy": 3, "moderate": 6, "hard": 8][onboarding]
    }

    /// Allure seuil selon le ressenti : facile ≤ 4, modéré 5 à 7 ou inconnu, dur ≥ 8 (Riegel vers 10 km).
    public static func thresholdSPerKm(distanceM: Double, durationS: Double, effort: Int?) -> Double {
        let pace = durationS / (distanceM / 1000)
        switch effort ?? 6 {
        case ...4:
            return pace / 1.22
        case 8...:
            let tenKmS = durationS * pow(10 / (distanceM / 1000), 1.06)
            return tenKmS / 10
        default:
            return pace / 1.10
        }
    }

    public static func zone(_ kind: WorkoutKind, thresholdSPerKm t: Double) -> PaceRange? {
        let factors: (Double, Double)
        switch kind {
        case .recovery: factors = (1.30, 1.45)
        case .easy: factors = (1.18, 1.30)
        case .long: factors = (1.18, 1.32)
        case .tempo: factors = (1.00, 1.05)
        case .intervals: factors = (0.90, 0.96)
        case .strength, .race: return nil
        }
        return PaceRange(fastSPerKm: Int((t * factors.0).rounded()), slowSPerKm: Int((t * factors.1).rounded()))
    }

    /// Temps prévu sur la course : allure seuil × 1,06 × distance.
    public static func predictedRaceS(thresholdSPerKm: Double, distanceKm: Double) -> Double {
        thresholdSPerKm * 1.06 * distanceKm
    }

    /// Dans l'objectif à 3 % près : `onTrack` ; jusqu'à 15 % au-dessus : `ambitious` ; au-delà : `veryAmbitious`.
    public static func feasibility(predictedS: Double, targetS: Double) -> Feasibility {
        if predictedS <= targetS * 1.03 { return .onTrack }
        if predictedS <= targetS * 1.15 { return .ambitious }
        return .veryAmbitious
    }
}
