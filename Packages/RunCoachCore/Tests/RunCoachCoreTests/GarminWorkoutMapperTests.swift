import XCTest
@testable import RunCoachCore

final class GarminWorkoutMapperTests: XCTestCase {
    /// JSON aux clés triées, pour comparer deux corps sans dépendre de l'ordre des clés.
    private func canonical(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func steps(_ body: [String: Any]) throws -> [[String: Any]] {
        let segments = try XCTUnwrap(body["workoutSegments"] as? [[String: Any]])
        return try XCTUnwrap(segments.first?["workoutSteps"] as? [[String: Any]])
    }

    /// Le corps envoyé par la validation 2.0 (script hors dépôt), arrivé sur la Forerunner 745 le 2026-11-13.
    private let validated = #"""
    {"workoutName": "RC · Test RunCoach",
     "description": "Séance de test créée par RunCoach (validation 2.0). Elle sera supprimée.",
     "sportType": {"sportTypeId": 1, "sportTypeKey": "running", "displayOrder": 1},
     "estimatedDurationInSecs": 1260,
     "workoutSegments": [{"segmentOrder": 1,
       "sportType": {"sportTypeId": 1, "sportTypeKey": "running", "displayOrder": 1},
       "workoutSteps": [
        {"type": "ExecutableStepDTO", "stepOrder": 1,
         "stepType": {"stepTypeId": 1, "stepTypeKey": "warmup", "displayOrder": 1},
         "endCondition": {"conditionTypeId": 2, "conditionTypeKey": "time", "displayOrder": 2, "displayable": true},
         "endConditionValue": 600,
         "targetType": {"workoutTargetTypeId": 1, "workoutTargetTypeKey": "no.target", "displayOrder": 1}},
        {"type": "RepeatGroupDTO", "stepOrder": 2,
         "stepType": {"stepTypeId": 6, "stepTypeKey": "repeat", "displayOrder": 6},
         "numberOfIterations": 3, "smartRepeat": false, "endConditionValue": 3,
         "endCondition": {"conditionTypeId": 7, "conditionTypeKey": "iterations", "displayOrder": 7, "displayable": false},
         "workoutSteps": [
          {"type": "ExecutableStepDTO", "stepOrder": 3,
           "stepType": {"stepTypeId": 3, "stepTypeKey": "interval", "displayOrder": 3},
           "endCondition": {"conditionTypeId": 3, "conditionTypeKey": "distance", "displayOrder": 3, "displayable": true},
           "endConditionValue": 400,
           "targetType": {"workoutTargetTypeId": 6, "workoutTargetTypeKey": "pace.zone", "displayOrder": 6},
           "targetValueOne": 2.9412, "targetValueTwo": 3.0769},
          {"type": "ExecutableStepDTO", "stepOrder": 4,
           "stepType": {"stepTypeId": 4, "stepTypeKey": "recovery", "displayOrder": 4},
           "endCondition": {"conditionTypeId": 2, "conditionTypeKey": "time", "displayOrder": 2, "displayable": true},
           "endConditionValue": 90,
           "targetType": {"workoutTargetTypeId": 1, "workoutTargetTypeKey": "no.target", "displayOrder": 1}}]},
        {"type": "ExecutableStepDTO", "stepOrder": 5,
         "stepType": {"stepTypeId": 2, "stepTypeKey": "cooldown", "displayOrder": 2},
         "endCondition": {"conditionTypeId": 2, "conditionTypeKey": "time", "displayOrder": 2, "displayable": true},
         "endConditionValue": 300,
         "targetType": {"workoutTargetTypeId": 1, "workoutTargetTypeKey": "no.target", "displayOrder": 1}}]}]}
    """#

    func testIntervalsMatchTheBodyValidatedOnTheWatch() throws {
        let spec = WorkoutSpec(
            date: "2026-11-18", kind: .intervals, title: "Test RunCoach",
            rationale: "Séance de test créée par RunCoach (validation 2.0). Elle sera supprimée.",
            estimatedDurationMin: 21, estimatedDistanceKm: nil,
            blocks: [
                WorkoutBlock(steps: [WorkoutStep(intent: .warmup, end: .time, value: 600)]),
                WorkoutBlock(repeatCount: 3, steps: [
                    WorkoutStep(intent: .run, end: .distance, value: 400, target: .pace(325, 340)),
                    WorkoutStep(intent: .recover, end: .time, value: 90),
                ]),
                WorkoutBlock(steps: [WorkoutStep(intent: .cooldown, end: .time, value: 300)]),
            ])
        XCTAssertEqual(try canonical(GarminWorkoutMapper.body(spec)), try canonical(Data(validated.utf8)))
    }

    func testHeartRateZoneLapButtonAndNotes() throws {
        let spec = WorkoutSpec(date: "2026-11-18", kind: .easy, title: "Footing", rationale: "r",
                               estimatedDurationMin: 30, estimatedDistanceKm: 5,
                               blocks: [WorkoutBlock(steps: [
                                   WorkoutStep(intent: .run, end: .lapButton, value: nil,
                                               target: WorkoutTarget(type: .hrZone, hrZone: 2), note: "Tranquille"),
                               ])])
        let step = try XCTUnwrap(steps(object(GarminWorkoutMapper.body(spec))).first)
        XCTAssertEqual((step["endCondition"] as? [String: Any])?["conditionTypeKey"] as? String, "lap.button")
        XCTAssertNil(step["endConditionValue"])
        XCTAssertEqual((step["targetType"] as? [String: Any])?["workoutTargetTypeKey"] as? String, "heart.rate.zone")
        XCTAssertEqual(step["zoneNumber"] as? Int, 2)
        XCTAssertEqual(step["description"] as? String, "Tranquille")
    }

    func testStrengthBecomesRepeatGroupsWithGarminExercises() throws {
        let spec = WorkoutSpec(date: "2026-11-18", kind: .strength, title: "Renfo", rationale: "r",
                               estimatedDurationMin: 20, estimatedDistanceKm: nil,
                               exercises: [
                                   StrengthExercise(exerciseId: "squat", sets: 3, reps: 12, restS: 60),
                                   StrengthExercise(exerciseId: "plank", sets: 2, durationS: 45, restS: 30),
                               ])
        let body = try object(GarminWorkoutMapper.body(spec))
        XCTAssertEqual((body["sportType"] as? [String: Any])?["sportTypeKey"] as? String, "strength_training")
        let groups = try steps(body)
        XCTAssertEqual(groups.map { $0["stepOrder"] as? Int }, [1, 4])
        XCTAssertEqual(groups.map { $0["numberOfIterations"] as? Int }, [3, 2])

        let squat = try XCTUnwrap(groups[0]["workoutSteps"] as? [[String: Any]])
        XCTAssertEqual(squat.map { $0["stepOrder"] as? Int }, [2, 3])
        XCTAssertEqual(squat[0]["category"] as? String, "SQUAT")
        XCTAssertEqual(squat[0]["exerciseName"] as? String, "SQUAT")
        XCTAssertEqual((squat[0]["endCondition"] as? [String: Any])?["conditionTypeId"] as? Int, 10)
        XCTAssertEqual(squat[0]["endConditionValue"] as? Int, 12)
        XCTAssertEqual((squat[1]["stepType"] as? [String: Any])?["stepTypeKey"] as? String, "rest")
        XCTAssertEqual(squat[1]["endConditionValue"] as? Int, 60)

        let plank = try XCTUnwrap(groups[1]["workoutSteps"] as? [[String: Any]])
        XCTAssertEqual((plank[0]["endCondition"] as? [String: Any])?["conditionTypeKey"] as? String, "time")
        XCTAssertEqual(plank[0]["endConditionValue"] as? Int, 45)
    }

    func testEveryCatalogExerciseHasAGarminEquivalent() {
        XCTAssertEqual(Set(StrengthCatalog.garmin.keys), Set(StrengthCatalog.ids))
    }

    func testEmptyWorkoutStillHasOneStep() throws {
        let spec = WorkoutSpec(date: "2026-11-18", kind: .race, title: "Course", rationale: "r",
                               estimatedDurationMin: 120, estimatedDistanceKm: 21.1)
        XCTAssertEqual(try steps(object(GarminWorkoutMapper.body(spec))).count, 1)
    }
}
