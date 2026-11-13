import Foundation

// Réponses JSON de Garmin. Noms de champs relevés sur le compte de l'utilisateur le 2026-11-13 (tâche 2.0).
// Tout est optionnel : un champ absent ne doit jamais faire échouer un import.

struct TokenResponseDTO: Decodable {
    var accessToken: String?
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

/// Élément de `/activitylist-service/activities/search/activities`.
public struct ActivityDTO: Decodable, Sendable {
    public struct ActivityType: Decodable, Sendable { public var typeKey: String? }

    public var activityId: Int64?
    public var activityName: String?
    /// `yyyy-MM-dd HH:mm:ss`, UTC.
    public var startTimeGMT: String?
    /// `yyyy-MM-dd HH:mm:ss`, heure locale du lieu de l'activité.
    public var startTimeLocal: String?
    /// Millisecondes depuis 1970.
    public var beginTimestamp: Double?
    public var activityType: ActivityType?
    public var distance: Double?
    public var duration: Double?
    public var movingDuration: Double?
    public var averageSpeed: Double?
    public var maxSpeed: Double?
    public var averageHR: Double?
    public var maxHR: Double?
    public var averageRunningCadenceInStepsPerMinute: Double?
    public var elevationGain: Double?
    public var elevationLoss: Double?
    public var calories: Double?
    public var vO2MaxValue: Double?
    public var aerobicTrainingEffect: Double?
    public var anaerobicTrainingEffect: Double?
    public var activityTrainingLoad: Double?
    public var minTemperature: Double?
    public var maxTemperature: Double?
    public var locationName: String?
    public var hasPolyline: Bool?
    public var hrTimeInZone_1: Double?
    public var hrTimeInZone_2: Double?
    public var hrTimeInZone_3: Double?
    public var hrTimeInZone_4: Double?
    public var hrTimeInZone_5: Double?
}

/// `/activity-service/activity/{id}/details` : colonnes décrites par `metricDescriptors`, valeurs par ligne.
/// Les valeurs sont déjà dans l'unité annoncée (le champ `factor` de Garmin ne s'applique pas).
public struct ActivityDetailsDTO: Decodable, Sendable {
    public struct Descriptor: Decodable, Sendable {
        public var metricsIndex: Int?
        public var key: String?
    }
    public struct Row: Decodable, Sendable {
        public var metrics: [Double?]?
    }
    public var metricDescriptors: [Descriptor]?
    public var activityDetailMetrics: [Row]?
}

/// `/sleep-service/sleep/dailySleepData`.
public struct SleepDTO: Decodable, Sendable {
    public struct Daily: Decodable, Sendable {
        public struct Scores: Decodable, Sendable {
            public struct Overall: Decodable, Sendable { public var value: Int? }
            public var overall: Overall?
        }
        public var sleepTimeSeconds: Double?
        public var sleepScores: Scores?
    }
    public var dailySleepDTO: Daily?
    public var restingHeartRate: Int?
}

/// `/metrics-service/metrics/trainingstatus/aggregated/{jour}` : contient aussi la dernière VO2max.
public struct TrainingStatusDTO: Decodable, Sendable {
    public struct VO2Max: Decodable, Sendable {
        public struct Generic: Decodable, Sendable {
            public var vo2MaxPreciseValue: Double?
            public var vo2MaxValue: Double?
        }
        public var generic: Generic?
    }
    public struct Status: Decodable, Sendable {
        public struct Device: Decodable, Sendable {
            public var trainingStatusFeedbackPhrase: String?
            public var primaryTrainingDevice: Bool?
        }
        /// Indexé par identifiant de montre.
        public var latestTrainingStatusData: [String: Device]?
    }
    public var mostRecentVO2Max: VO2Max?
    public var mostRecentTrainingStatus: Status?
}

/// `/userprofile-service/socialProfile`.
public struct SocialProfileDTO: Decodable, Sendable {
    public var displayName: String?
    public var fullName: String?
}
