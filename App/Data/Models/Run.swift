import Foundation
import SwiftData
import RunCoachCore

/// Une activité importée de Garmin. Tout champ venant de Garmin est optionnel.
@Model
final class Run {
    @Attribute(.unique) var garminActivityId: Int64
    var name: String
    /// UTC
    var startDate: Date
    /// Jour local `yyyy-MM-dd`
    var dayKey: String
    var activityType: String
    var distanceM: Double
    var durationS: Double
    var movingDurationS: Double?
    var avgSpeedMps: Double?
    var maxSpeedMps: Double?
    var avgHR: Int?
    var maxHR: Int?
    var avgCadenceSpm: Double?
    var elevationGainM: Double?
    var elevationLossM: Double?
    var calories: Double?
    var avgTemperatureC: Double?
    var vo2max: Double?
    var aerobicTE: Double?
    var anaerobicTE: Double?
    /// Charge Garmin, affichage seul.
    var garminLoad: Double?
    /// Charge calculée par l'app.
    var edwardsLoad: Double?
    /// 5 valeurs, vide si inconnu.
    var hrZoneSeconds: [Double]
    var locationName: String?
    /// `summaryOnly` / `complete` / `failed`
    var detailState: String
    /// Ressenti 1 à 10, saisi par l'utilisateur.
    var perceivedEffort: Int?
    var userNote: String?

    @Relationship(deleteRule: .cascade, inverse: \Split.run) var splits: [Split]
    @Relationship(deleteRule: .cascade, inverse: \RunTrack.run) var track: RunTrack?
    var plannedWorkout: PlannedWorkout?

    init(garminActivityId: Int64, name: String, startDate: Date, activityType: String = "running",
         distanceM: Double, durationS: Double) {
        self.garminActivityId = garminActivityId
        self.name = name
        self.startDate = startDate
        self.dayKey = DayKey.key(startDate)
        self.activityType = activityType
        self.distanceM = distanceM
        self.durationS = durationS
        self.hrZoneSeconds = []
        self.detailState = "summaryOnly"
        self.splits = []
    }

    var paceSPerKm: Double {
        distanceM > 0 ? durationS / (distanceM / 1000) : 0
    }

    var sortedSplits: [Split] {
        splits.sorted { $0.index < $1.index }
    }

    /// Décode le tracé. Coûteux : à appeler une fois, hors du corps d'une vue.
    func loadTrack() -> Track? {
        guard let data = track?.samplesData else { return nil }
        return try? JSONDecoder().decode(Track.self, from: data)
    }
}

@Model
final class Split {
    var index: Int
    var distanceM: Double
    var durationS: Double
    var avgSpeedMps: Double?
    var avgHR: Int?
    var avgCadenceSpm: Double?
    var elevationGainM: Double?
    var elevationLossM: Double?
    var run: Run?

    init(index: Int, distanceM: Double, durationS: Double) {
        self.index = index
        self.distanceM = distanceM
        self.durationS = durationS
    }

    var paceSPerKm: Double {
        distanceM > 0 ? durationS / (distanceM / 1000) : 0
    }
}

/// Tracé complet d'une sortie, stocké d'un bloc (ARCHITECTURE.md §4.1 : pas une entité par point).
@Model
final class RunTrack {
    @Attribute(.externalStorage) var samplesData: Data
    var sampleCount: Int
    var run: Run?

    init(track: Track) {
        self.samplesData = (try? JSONEncoder().encode(track)) ?? Data()
        self.sampleCount = track.count
    }
}
