import Foundation
import SwiftData
import RunCoachCore

/// Une activité importée de Garmin : course, mais aussi renforcement (sans distance ni tracé).
/// Tout champ venant de Garmin est optionnel.
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
    /// Échecs du téléchargement des détails ; `failed` à 3.
    var detailAttempts: Int = 0
    /// Ressenti 1 à 10, saisi par l'utilisateur.
    var perceivedEffort: Int?
    var userNote: String?
    /// Meilleurs temps sur 1, 5 et 10 km pris dans la sortie (records, étape 7). Optionnels : ajoutés sur une base
    /// installée ; `bestsComputed` dit s'ils ont été calculés (nil reste possible pour une sortie trop courte).
    var best1kS: Double?
    var best5kS: Double?
    var best10kS: Double?
    var bestsComputed: Bool?

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

    /// Activité lue dans la liste Garmin. Sans tracé à télécharger, elle est complète tout de suite.
    convenience init(imported a: ImportedActivity) {
        self.init(garminActivityId: a.garminActivityId, name: a.name, startDate: a.startDate,
                  activityType: a.activityType, distanceM: a.distanceM, durationS: a.durationS)
        dayKey = a.dayKey
        movingDurationS = a.movingDurationS
        avgSpeedMps = a.avgSpeedMps
        maxSpeedMps = a.maxSpeedMps
        avgHR = a.avgHR
        maxHR = a.maxHR
        avgCadenceSpm = a.avgCadenceSpm
        elevationGainM = a.elevationGainM
        elevationLossM = a.elevationLossM
        calories = a.calories
        avgTemperatureC = a.avgTemperatureC
        vo2max = a.vo2max
        aerobicTE = a.aerobicTE
        anaerobicTE = a.anaerobicTE
        garminLoad = a.garminLoad
        hrZoneSeconds = a.hrZoneSeconds
        locationName = a.locationName
        detailState = a.hasTrack ? "summaryOnly" : "complete"
    }

    /// Tracé et kilomètres tirés des détails Garmin (`nil` : activité sans GPS exploitable).
    func applyDetails(_ samples: Track?) {
        detailState = "complete"
        guard let samples else { return }
        track = RunTrack(track: samples)
        splits = samples.kmSplits().map(Split.init(km:))
        computeBests(samples)
    }

    /// Course à pied (route, trail, tapis) : seules ces sorties comptent pour les records.
    var isRunning: Bool { activityType.contains("running") }

    func computeBests(_ samples: Track) {
        bestsComputed = true
        guard isRunning else { return }
        best1kS = PersonalRecords.bestEffortS(samples, distanceM: 1000)
        best5kS = PersonalRecords.bestEffortS(samples, distanceM: 5000)
        best10kS = PersonalRecords.bestEffortS(samples, distanceM: 10000)
    }

    func best(_ distanceM: Double) -> Double? {
        switch distanceM {
        case 1000: return best1kS
        case 5000: return best5kS
        default: return best10kS
        }
    }

    /// Records battus par cette sortie au moment où elle a été courue (« 5 km en 24:31 »), comparés aux sorties d'avant.
    func records(among runs: [Run]) -> [String] {
        guard isRunning, bestsComputed == true else { return [] }
        let before = runs.filter { $0.isRunning && $0.startDate < startDate }
        var out: [String] = []
        for d in PersonalRecords.distancesM where PersonalRecords.isRecord(best(d), previous: before.compactMap { $0.best(d) }) {
            out.append("\(Int(d / 1000)) km en \(Fmt.duration(best(d) ?? 0))")
        }
        // La plus longue sortie ne compte qu'à partir de 5 km : sinon la toute première sortie est un « record ».
        if distanceM >= 5000, PersonalRecords.isRecord(distanceM, previous: before.map(\.distanceM), higherIsBetter: true) {
            out.append("plus longue sortie : \(Fmt.km(distanceM, decimals: 1)) km")
        }
        return out
    }

    /// Records de l'historique importé avant l'étape 7 : calculés une fois, en rendant la main entre deux sorties.
    @MainActor
    static func fillMissingBests(context: ModelContext) async {
        let pending = ((try? context.fetch(FetchDescriptor<Run>())) ?? []).filter { $0.bestsComputed != true && $0.track != nil }
        for (i, run) in pending.enumerated() {
            if let data = run.track?.samplesData, let samples = try? JSONDecoder().decode(Track.self, from: data) {
                run.computeBests(samples)
            } else {
                run.bestsComputed = true
            }
            if i % 10 == 9 {
                try? context.save()
                await Task.yield()
            }
        }
        if !pending.isEmpty { try? context.save() }
    }

    var paceSPerKm: Double {
        distanceM > 0 ? durationS / (distanceM / 1000) : 0
    }

    var isStrength: Bool {
        activityType == "strength_training"
    }

    var sortedSplits: [Split] {
        splits.sorted { $0.index < $1.index }
    }

    /// Décode le tracé, positions lissées pour l'affichage (la base garde les relevés bruts).
    /// Coûteux : à appeler une fois, hors du corps d'une vue.
    func loadTrack() -> Track? {
        guard let data = track?.samplesData else { return nil }
        return (try? JSONDecoder().decode(Track.self, from: data))?.smoothed(windowM: 10)
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

    convenience init(km: KmSplit) {
        self.init(index: km.index, distanceM: km.distanceM, durationS: km.durationS)
        avgSpeedMps = km.avgSpeedMps
        avgHR = km.avgHR
        avgCadenceSpm = km.avgCadenceSpm
        elevationGainM = km.elevationGainM
        elevationLossM = km.elevationLossM
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
