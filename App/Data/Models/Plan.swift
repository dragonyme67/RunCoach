import Foundation
import SwiftData
import RunCoachCore

@Model
final class TrainingPlan {
    var uuid: UUID
    var createdAt: Date
    var goal: Goal?
    /// `[MacroWeek]` en JSON.
    var macroWeeksData: Data
    var isActive: Bool
    @Relationship(deleteRule: .cascade, inverse: \PlannedWorkout.plan) var workouts: [PlannedWorkout]

    init(goal: Goal?, macroWeeks: [MacroWeek] = []) {
        self.uuid = UUID()
        self.createdAt = Date()
        self.goal = goal
        self.macroWeeksData = (try? JSONEncoder().encode(macroWeeks)) ?? Data()
        self.isActive = true
        self.workouts = []
    }

    var macroWeeks: [MacroWeek] {
        (try? JSONDecoder().decode([MacroWeek].self, from: macroWeeksData)) ?? []
    }
}

@Model
final class PlannedWorkout {
    var uuid: UUID
    var dayKey: String
    /// `WorkoutKind`
    var kind: String
    var title: String
    var rationale: String
    /// `WorkoutSpec` en JSON.
    var specData: Data
    var estimatedDurationMin: Int
    var estimatedDistanceKm: Double?
    /// `planned` / `done` / `missed` / `skipped` / `cancelled`
    var status: String
    /// `ai` / `fallback` / `user`
    var source: String
    var garminWorkoutId: Int64?
    var garminScheduleId: Int64?
    /// `notSent` / `sent` / `needsUpdate` / `failed`
    var garminSyncState: String
    var garminSyncError: String?
    @Relationship(inverse: \Run.plannedWorkout) var completedRun: Run?
    var plan: TrainingPlan?
    var updatedAt: Date

    init(spec: WorkoutSpec, status: String = "planned", source: String = "ai", garminSyncState: String = "notSent") {
        self.uuid = UUID()
        self.dayKey = spec.date
        self.kind = spec.kind.rawValue
        self.title = spec.title
        self.rationale = spec.rationale
        self.specData = (try? JSONEncoder().encode(spec)) ?? Data()
        self.estimatedDurationMin = spec.estimatedDurationMin
        self.estimatedDistanceKm = spec.estimatedDistanceKm
        self.status = status
        self.source = source
        self.garminSyncState = garminSyncState
        self.updatedAt = Date()
    }

    var kindValue: WorkoutKind {
        WorkoutKind(rawValue: kind) ?? .easy
    }

    var spec: WorkoutSpec? {
        try? JSONDecoder().decode(WorkoutSpec.self, from: specData)
    }
}
