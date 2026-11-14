import XCTest
@testable import RunCoachCore

final class WatchSyncTests: XCTestCase {
    func testMirrorsPlannedWorkoutsOfTheNextSevenDays() throws {
        let today = try XCTUnwrap(DayKey.date("2026-11-16"))
        let local = [
            WatchSync.Local(dayKey: "2026-11-16", status: "planned", garminWorkoutId: 10, state: "sent", attempts: 0),       // gardée
            WatchSync.Local(dayKey: "2026-11-17", status: "planned", garminWorkoutId: 11, state: "needsUpdate", attempts: 0), // remplacée
            WatchSync.Local(dayKey: "2026-11-18", status: "cancelled", garminWorkoutId: 12, state: "sent", attempts: 0),    // annulée
            WatchSync.Local(dayKey: "2026-11-19", status: "planned", garminWorkoutId: nil, state: "notSent", attempts: 0),  // nouvelle
            WatchSync.Local(dayKey: "2026-11-23", status: "planned", garminWorkoutId: nil, state: "notSent", attempts: 0),  // hors fenêtre
            WatchSync.Local(dayKey: "2026-11-15", status: "done", garminWorkoutId: 13, state: "sent", attempts: 0),         // passée
            WatchSync.Local(dayKey: "2026-11-20", status: "planned", garminWorkoutId: 14, state: "sent", attempts: 0),      // effacée chez Garmin
            WatchSync.Local(dayKey: "2026-11-21", status: "planned", garminWorkoutId: nil, state: "failed", attempts: 3),   // abandon
            WatchSync.Local(dayKey: "2026-11-22", status: "planned", garminWorkoutId: nil, state: "failed", attempts: 1),   // nouvel essai
        ]
        let remote = [
            WorkoutRefDTO(workoutId: 10, workoutName: "RC · Footing"),
            WorkoutRefDTO(workoutId: 11, workoutName: "RC · Tempo"),
            WorkoutRefDTO(workoutId: 12, workoutName: "RC · Renfo"),
            WorkoutRefDTO(workoutId: 13, workoutName: "RC · Sortie longue"),
            WorkoutRefDTO(workoutId: 99, workoutName: "RC · Séance supprimée de la base"),
            WorkoutRefDTO(workoutId: 50, workoutName: "Mon fractionné à moi"),
        ]
        let decision = WatchSync.decide(local: local, remote: remote, today: today)
        XCTAssertEqual(decision.delete, [11, 12, 13, 99], "jamais un workout sans le préfixe RC")
        XCTAssertEqual(decision.forget, [1, 2, 5, 6])
        XCTAssertEqual(decision.send, [1, 3, 6, 8])
    }

    func testNothingToDoWhenEverythingIsInPlace() throws {
        let today = try XCTUnwrap(DayKey.date("2026-11-16"))
        let local = [WatchSync.Local(dayKey: "2026-11-16", status: "planned", garminWorkoutId: 10, state: "sent", attempts: 0)]
        let decision = WatchSync.decide(local: local, remote: [WorkoutRefDTO(workoutId: 10, workoutName: "RC · Footing")], today: today)
        XCTAssertEqual(decision, WatchSync.Decision(delete: [], forget: [], send: []))
    }
}
