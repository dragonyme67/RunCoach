import Foundation

/// Métriques d'un jour, prêtes à copier dans l'entité `DailyMetric`. Tout est optionnel :
/// la Forerunner 745 ne fournit ni HRV ni disponibilité à l'entraînement (constaté le 2026-11-13).
public struct ImportedDailyMetric: Equatable, Sendable {
    public var dayKey: String
    public var sleepSeconds: Double?
    public var sleepScore: Int?
    public var restingHR: Int?
    public var vo2max: Double?
    /// Phrase de Garmin, par exemple `PRODUCTIVE_3` ou `RECOVERY_AER_LOW_SHORT`.
    public var trainingStatus: String?

    public init(dayKey: String, sleep: SleepDTO?, status: TrainingStatusDTO? = nil) {
        self.dayKey = dayKey
        sleepSeconds = sleep?.dailySleepDTO?.sleepTimeSeconds
        sleepScore = sleep?.dailySleepDTO?.sleepScores?.overall?.value
        restingHR = sleep?.restingHeartRate
        let vo2 = status?.mostRecentVO2Max?.generic
        vo2max = vo2?.vo2MaxPreciseValue ?? vo2?.vo2MaxValue
        // Plusieurs montres possibles : on garde celle que Garmin marque comme principale.
        let devices = status?.mostRecentTrainingStatus?.latestTrainingStatusData?.values.map { $0 } ?? []
        trainingStatus = (devices.first { $0.primaryTrainingDevice == true } ?? devices.first)?.trainingStatusFeedbackPhrase
    }
}
