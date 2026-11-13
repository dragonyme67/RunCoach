import Foundation

/// Résumé d'une activité Garmin, converti et prêt à copier dans l'entité `Run` de l'app.
public struct ImportedActivity: Equatable, Sendable {
    public var garminActivityId: Int64
    public var name: String
    public var startDate: Date
    /// Jour local du lieu de l'activité (`yyyy-MM-dd`).
    public var dayKey: String
    public var activityType: String
    public var distanceM: Double
    public var durationS: Double
    public var movingDurationS: Double?
    public var avgSpeedMps: Double?
    public var maxSpeedMps: Double?
    public var avgHR: Int?
    public var maxHR: Int?
    public var avgCadenceSpm: Double?
    public var elevationGainM: Double?
    public var elevationLossM: Double?
    public var calories: Double?
    public var avgTemperatureC: Double?
    public var vo2max: Double?
    public var aerobicTE: Double?
    public var anaerobicTE: Double?
    public var garminLoad: Double?
    /// 5 valeurs, ou vide si Garmin n'en donne aucune.
    public var hrZoneSeconds: [Double]
    public var locationName: String?
    /// Vrai si l'activité a un tracé GPS à télécharger (une requête de détails).
    public var hasTrack: Bool

    /// `nil` si l'identifiant, la date ou la durée manquent : l'activité est alors ignorée.
    public init?(_ dto: ActivityDTO) {
        guard let id = dto.activityId, let duration = dto.duration,
              let start = Self.date(gmt: dto.startTimeGMT) ?? dto.beginTimestamp.map({ Date(timeIntervalSince1970: $0 / 1000) })
        else { return nil }
        garminActivityId = id
        name = dto.activityName ?? ""
        startDate = start
        dayKey = dto.startTimeLocal.map { String($0.prefix(10)) } ?? DayKey.key(start)
        activityType = dto.activityType?.typeKey ?? "other"
        distanceM = dto.distance ?? 0
        durationS = duration
        movingDurationS = dto.movingDuration
        avgSpeedMps = dto.averageSpeed
        maxSpeedMps = dto.maxSpeed
        avgHR = dto.averageHR.map { Int($0.rounded()) }
        maxHR = dto.maxHR.map { Int($0.rounded()) }
        avgCadenceSpm = dto.averageRunningCadenceInStepsPerMinute
        elevationGainM = dto.elevationGain
        elevationLossM = dto.elevationLoss
        calories = dto.calories
        if let low = dto.minTemperature, let high = dto.maxTemperature { avgTemperatureC = (low + high) / 2 }
        vo2max = dto.vO2MaxValue
        aerobicTE = dto.aerobicTrainingEffect
        anaerobicTE = dto.anaerobicTrainingEffect
        garminLoad = dto.activityTrainingLoad
        let zones = [dto.hrTimeInZone_1, dto.hrTimeInZone_2, dto.hrTimeInZone_3, dto.hrTimeInZone_4, dto.hrTimeInZone_5]
        hrZoneSeconds = zones.allSatisfy { $0 == nil } ? [] : zones.map { $0 ?? 0 }
        locationName = dto.locationName
        hasTrack = dto.hasPolyline ?? false
    }

    private static let gmtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func date(gmt: String?) -> Date? {
        gmt.flatMap { gmtFormatter.date(from: String($0.prefix(19)).replacingOccurrences(of: "T", with: " ")) }
    }
}
