import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import RunCoachCore

/// Sauvegarde complète des données locales dans un fichier JSON, et restauration (étape 7, n° 1).
/// Sert à changer d'installation (Sideloadly → SideStore, nouvel iPhone) sans rien perdre.
/// Ni les jetons Garmin ni la clé IA n'y sont : ils restent dans le Keychain (§9.4) ; après une restauration sur
/// une nouvelle installation, il suffit de se reconnecter à Garmin une fois et de recoller la clé.
enum Backup {
    static let formatVersion = 1

    enum Failure: LocalizedError {
        case unreadable, newerFormat
        var errorDescription: String? {
            switch self {
            case .unreadable: return "Ce fichier n'est pas une sauvegarde RunCoach lisible."
            case .newerFormat: return "Cette sauvegarde vient d'une version plus récente de l'app : mets l'app à jour."
            }
        }
    }

    // MARK: - Format du fichier

    struct File: Codable {
        var formatVersion: Int
        var exportedAt: Date
        var profile: Profile?
        var goals: [GoalItem]
        var plans: [PlanItem]
        var runs: [RunItem]
        var dailyMetrics: [MetricItem]
        var chat: [MessageItem]
        var sync: SyncItem?
    }

    struct Profile: Codable {
        var firstName: String, birthDate: Date, sex: String?, heightCm: Double?, weightKg: Double?
        var runningSince: Date, recentRunDistanceM: Double, recentRunDurationS: Double, recentRunEffort: String
        var thresholdPaceOverrideSPerKm: Double?, availableWeekdays: [Int], longRunWeekday: Int, maxSessionMinutes: Int
        var hrMax: Int?, hrRest: Int?, injuryNote: String, currentPain: Bool, painLevel: String?, fatigueLevel: String
        var wantsStrength: Bool, strengthEquipment: String, trainingPreference: String?
        var medicalDisclaimerAcceptedAt: Date?, updatedAt: Date
    }

    struct GoalItem: Codable {
        var uuid: UUID, kind: String, name: String, raceDistanceM: Double?, raceDate: Date?, targetTimeS: Double?, isActive: Bool
    }

    struct PlanItem: Codable {
        var uuid: UUID, createdAt: Date, goalUUID: UUID?, macroWeeksData: Data, isActive: Bool
        var workouts: [WorkoutItem]
    }

    struct WorkoutItem: Codable {
        var uuid: UUID, dayKey: String, kind: String, title: String, rationale: String, specData: Data
        var estimatedDurationMin: Int, estimatedDistanceKm: Double?, status: String, source: String
        var garminWorkoutId: Int64?, garminScheduleId: Int64?, garminSyncState: String, garminSyncError: String?
        var garminAttempts: Int?, updatedAt: Date
    }

    struct RunItem: Codable {
        var garminActivityId: Int64, name: String, startDate: Date, dayKey: String, activityType: String
        var distanceM: Double, durationS: Double, movingDurationS: Double?, avgSpeedMps: Double?, maxSpeedMps: Double?
        var avgHR: Int?, maxHR: Int?, avgCadenceSpm: Double?, elevationGainM: Double?, elevationLossM: Double?
        var calories: Double?, avgTemperatureC: Double?, vo2max: Double?, aerobicTE: Double?, anaerobicTE: Double?
        var garminLoad: Double?, edwardsLoad: Double?, hrZoneSeconds: [Double], locationName: String?
        var detailState: String, detailAttempts: Int, perceivedEffort: Int?, userNote: String?
        var best1kS: Double?, best5kS: Double?, best10kS: Double?, bestsComputed: Bool?
        var splits: [SplitItem], trackData: Data?, trackSampleCount: Int?, plannedWorkoutUUID: UUID?
    }

    struct SplitItem: Codable {
        var index: Int, distanceM: Double, durationS: Double, avgSpeedMps: Double?, avgHR: Int?
        var avgCadenceSpm: Double?, elevationGainM: Double?, elevationLossM: Double?
    }

    struct MetricItem: Codable {
        var dayKey: String, sleepSeconds: Double?, sleepScore: Int?, hrvLastNightMs: Double?, hrvStatus: String?
        var restingHR: Int?, vo2max: Double?, trainingReadiness: Int?, trainingStatus: String?, bodyBattery: Int?
    }

    struct MessageItem: Codable {
        var uuid: UUID, role: String, text: String, createdAt: Date, actionsData: Data?, actionLines: [String], actionsState: String
    }

    struct SyncItem: Codable {
        var lastGarminSyncAt: Date?
        var backfillDone: Bool
        var garminDisplayName: String?
    }

    // MARK: - Export

    @MainActor
    static func export(_ context: ModelContext) throws -> Data {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let file = File(
            formatVersion: formatVersion,
            exportedAt: Date(),
            profile: all(AthleteProfile.self).first.map { p in
                Profile(firstName: p.firstName, birthDate: p.birthDate, sex: p.sex, heightCm: p.heightCm, weightKg: p.weightKg,
                        runningSince: p.runningSince, recentRunDistanceM: p.recentRunDistanceM,
                        recentRunDurationS: p.recentRunDurationS, recentRunEffort: p.recentRunEffort,
                        thresholdPaceOverrideSPerKm: p.thresholdPaceOverrideSPerKm, availableWeekdays: p.availableWeekdays,
                        longRunWeekday: p.longRunWeekday, maxSessionMinutes: p.maxSessionMinutes, hrMax: p.hrMax,
                        hrRest: p.hrRest, injuryNote: p.injuryNote, currentPain: p.currentPain, painLevel: p.painLevel,
                        fatigueLevel: p.fatigueLevel, wantsStrength: p.wantsStrength, strengthEquipment: p.strengthEquipment,
                        trainingPreference: p.trainingPreference, medicalDisclaimerAcceptedAt: p.medicalDisclaimerAcceptedAt,
                        updatedAt: p.updatedAt)
            },
            goals: all(Goal.self).map {
                GoalItem(uuid: $0.uuid, kind: $0.kind, name: $0.name, raceDistanceM: $0.raceDistanceM, raceDate: $0.raceDate,
                         targetTimeS: $0.targetTimeS, isActive: $0.isActive)
            },
            plans: all(TrainingPlan.self).map { plan in
                PlanItem(uuid: plan.uuid, createdAt: plan.createdAt, goalUUID: plan.goal?.uuid, macroWeeksData: plan.macroWeeksData,
                         isActive: plan.isActive, workouts: plan.workouts.map { w in
                    WorkoutItem(uuid: w.uuid, dayKey: w.dayKey, kind: w.kind, title: w.title, rationale: w.rationale,
                                specData: w.specData, estimatedDurationMin: w.estimatedDurationMin,
                                estimatedDistanceKm: w.estimatedDistanceKm, status: w.status, source: w.source,
                                garminWorkoutId: w.garminWorkoutId, garminScheduleId: w.garminScheduleId,
                                garminSyncState: w.garminSyncState, garminSyncError: w.garminSyncError,
                                garminAttempts: w.garminAttempts, updatedAt: w.updatedAt)
                })
            },
            runs: all(Run.self).map { r in
                RunItem(garminActivityId: r.garminActivityId, name: r.name, startDate: r.startDate, dayKey: r.dayKey,
                        activityType: r.activityType, distanceM: r.distanceM, durationS: r.durationS,
                        movingDurationS: r.movingDurationS, avgSpeedMps: r.avgSpeedMps, maxSpeedMps: r.maxSpeedMps,
                        avgHR: r.avgHR, maxHR: r.maxHR, avgCadenceSpm: r.avgCadenceSpm, elevationGainM: r.elevationGainM,
                        elevationLossM: r.elevationLossM, calories: r.calories, avgTemperatureC: r.avgTemperatureC,
                        vo2max: r.vo2max, aerobicTE: r.aerobicTE, anaerobicTE: r.anaerobicTE, garminLoad: r.garminLoad,
                        edwardsLoad: r.edwardsLoad, hrZoneSeconds: r.hrZoneSeconds, locationName: r.locationName,
                        detailState: r.detailState, detailAttempts: r.detailAttempts, perceivedEffort: r.perceivedEffort,
                        userNote: r.userNote, best1kS: r.best1kS, best5kS: r.best5kS, best10kS: r.best10kS,
                        bestsComputed: r.bestsComputed,
                        splits: r.splits.map {
                            SplitItem(index: $0.index, distanceM: $0.distanceM, durationS: $0.durationS, avgSpeedMps: $0.avgSpeedMps,
                                      avgHR: $0.avgHR, avgCadenceSpm: $0.avgCadenceSpm, elevationGainM: $0.elevationGainM,
                                      elevationLossM: $0.elevationLossM)
                        },
                        trackData: r.track?.samplesData, trackSampleCount: r.track?.sampleCount,
                        plannedWorkoutUUID: r.plannedWorkout?.uuid)
            },
            dailyMetrics: all(DailyMetric.self).map {
                MetricItem(dayKey: $0.dayKey, sleepSeconds: $0.sleepSeconds, sleepScore: $0.sleepScore,
                           hrvLastNightMs: $0.hrvLastNightMs, hrvStatus: $0.hrvStatus, restingHR: $0.restingHR,
                           vo2max: $0.vo2max, trainingReadiness: $0.trainingReadiness, trainingStatus: $0.trainingStatus,
                           bodyBattery: $0.bodyBattery)
            },
            chat: all(ChatMessage.self).map {
                MessageItem(uuid: $0.uuid, role: $0.role, text: $0.text, createdAt: $0.createdAt, actionsData: $0.actionsData,
                            actionLines: $0.actionLines, actionsState: $0.actionsState)
            },
            sync: all(SyncState.self).first.map {
                SyncItem(lastGarminSyncAt: $0.lastGarminSyncAt, backfillDone: $0.backfillDone, garminDisplayName: $0.garminDisplayName)
            })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    // MARK: - Restauration

    /// Remplace toutes les données locales par celles du fichier. Le fichier est entièrement lu et vérifié avant
    /// que quoi que ce soit soit effacé : un fichier illisible ne touche à rien.
    @MainActor
    static func restore(_ data: Data, into context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data) else { throw Failure.unreadable }
        guard file.formatVersion <= formatVersion else { throw Failure.newerFormat }

        // Un par un plutôt qu'en lot : les règles de suppression (cascade des kilomètres, du tracé et des séances
        // d'un plan, mise à nil des liens sortie ↔ séance) s'appliquent alors à coup sûr.
        func wipe<T: PersistentModel>(_ type: T.Type) {
            for object in (try? context.fetch(FetchDescriptor<T>())) ?? [] { context.delete(object) }
        }
        wipe(Run.self)
        wipe(TrainingPlan.self)
        wipe(PlannedWorkout.self)
        wipe(Goal.self)
        wipe(AthleteProfile.self)
        wipe(DailyMetric.self)
        wipe(ChatMessage.self)
        wipe(SyncState.self)
        try context.save()

        if let p = file.profile {
            let profile = AthleteProfile(firstName: p.firstName, birthDate: p.birthDate, runningSince: p.runningSince,
                                         recentRunDistanceM: p.recentRunDistanceM, recentRunDurationS: p.recentRunDurationS,
                                         recentRunEffort: p.recentRunEffort, availableWeekdays: p.availableWeekdays,
                                         longRunWeekday: p.longRunWeekday, maxSessionMinutes: p.maxSessionMinutes)
            context.insert(profile)
            profile.sex = p.sex
            profile.heightCm = p.heightCm
            profile.weightKg = p.weightKg
            profile.thresholdPaceOverrideSPerKm = p.thresholdPaceOverrideSPerKm
            profile.hrMax = p.hrMax
            profile.hrRest = p.hrRest
            profile.injuryNote = p.injuryNote
            profile.currentPain = p.currentPain
            profile.painLevel = p.painLevel
            profile.fatigueLevel = p.fatigueLevel
            profile.wantsStrength = p.wantsStrength
            profile.strengthEquipment = p.strengthEquipment
            profile.trainingPreference = p.trainingPreference
            profile.medicalDisclaimerAcceptedAt = p.medicalDisclaimerAcceptedAt
            profile.updatedAt = p.updatedAt
        }

        var goals: [UUID: Goal] = [:]
        for g in file.goals {
            let goal = Goal(kind: g.kind, name: g.name, raceDistanceM: g.raceDistanceM, raceDate: g.raceDate,
                            targetTimeS: g.targetTimeS, isActive: g.isActive)
            context.insert(goal)
            goal.uuid = g.uuid
            goals[g.uuid] = goal
        }

        var workouts: [UUID: PlannedWorkout] = [:]
        for p in file.plans {
            let plan = TrainingPlan(goal: nil)
            context.insert(plan)
            plan.uuid = p.uuid
            plan.createdAt = p.createdAt
            plan.goal = p.goalUUID.flatMap { goals[$0] }
            plan.macroWeeksData = p.macroWeeksData
            plan.isActive = p.isActive
            for w in p.workouts {
                guard let spec = try? JSONDecoder().decode(WorkoutSpec.self, from: w.specData) else { continue }
                let workout = PlannedWorkout(spec: spec, status: w.status, source: w.source, garminSyncState: w.garminSyncState)
                context.insert(workout)
                workout.uuid = w.uuid
                workout.dayKey = w.dayKey
                workout.kind = w.kind
                workout.title = w.title
                workout.rationale = w.rationale
                workout.specData = w.specData
                workout.estimatedDurationMin = w.estimatedDurationMin
                workout.estimatedDistanceKm = w.estimatedDistanceKm
                workout.garminWorkoutId = w.garminWorkoutId
                workout.garminScheduleId = w.garminScheduleId
                workout.garminSyncError = w.garminSyncError
                workout.garminAttempts = w.garminAttempts
                workout.updatedAt = w.updatedAt
                workout.plan = plan
                workouts[w.uuid] = workout
            }
        }

        for r in file.runs {
            let run = Run(garminActivityId: r.garminActivityId, name: r.name, startDate: r.startDate,
                          activityType: r.activityType, distanceM: r.distanceM, durationS: r.durationS)
            context.insert(run)
            run.dayKey = r.dayKey
            run.movingDurationS = r.movingDurationS
            run.avgSpeedMps = r.avgSpeedMps
            run.maxSpeedMps = r.maxSpeedMps
            run.avgHR = r.avgHR
            run.maxHR = r.maxHR
            run.avgCadenceSpm = r.avgCadenceSpm
            run.elevationGainM = r.elevationGainM
            run.elevationLossM = r.elevationLossM
            run.calories = r.calories
            run.avgTemperatureC = r.avgTemperatureC
            run.vo2max = r.vo2max
            run.aerobicTE = r.aerobicTE
            run.anaerobicTE = r.anaerobicTE
            run.garminLoad = r.garminLoad
            run.edwardsLoad = r.edwardsLoad
            run.hrZoneSeconds = r.hrZoneSeconds
            run.locationName = r.locationName
            run.detailState = r.detailState
            run.detailAttempts = r.detailAttempts
            run.perceivedEffort = r.perceivedEffort
            run.userNote = r.userNote
            run.best1kS = r.best1kS
            run.best5kS = r.best5kS
            run.best10kS = r.best10kS
            run.bestsComputed = r.bestsComputed
            run.splits = r.splits.map { s in
                let split = Split(index: s.index, distanceM: s.distanceM, durationS: s.durationS)
                split.avgSpeedMps = s.avgSpeedMps
                split.avgHR = s.avgHR
                split.avgCadenceSpm = s.avgCadenceSpm
                split.elevationGainM = s.elevationGainM
                split.elevationLossM = s.elevationLossM
                return split
            }
            if let data = r.trackData {
                let track = RunTrack(track: Track(t: [], lat: [], lon: [], dist: []))
                track.samplesData = data
                track.sampleCount = r.trackSampleCount ?? 0
                run.track = track
            }
            run.plannedWorkout = r.plannedWorkoutUUID.flatMap { workouts[$0] }
        }

        for m in file.dailyMetrics {
            let metric = DailyMetric(dayKey: m.dayKey)
            context.insert(metric)
            metric.sleepSeconds = m.sleepSeconds
            metric.sleepScore = m.sleepScore
            metric.hrvLastNightMs = m.hrvLastNightMs
            metric.hrvStatus = m.hrvStatus
            metric.restingHR = m.restingHR
            metric.vo2max = m.vo2max
            metric.trainingReadiness = m.trainingReadiness
            metric.trainingStatus = m.trainingStatus
            metric.bodyBattery = m.bodyBattery
        }

        for c in file.chat {
            let message = ChatMessage(role: c.role, text: c.text, createdAt: c.createdAt,
                                      actionLines: c.actionLines, actionsState: c.actionsState)
            context.insert(message)
            message.uuid = c.uuid
            message.actionsData = c.actionsData
        }

        if let s = file.sync {
            let state = SyncState()
            context.insert(state)
            state.lastGarminSyncAt = s.lastGarminSyncAt
            state.backfillDone = s.backfillDone
            state.garminDisplayName = s.garminDisplayName
        }
        try context.save()
    }
}

/// Fichier de sauvegarde pour `fileExporter`.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
