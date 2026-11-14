import XCTest
@testable import RunCoachCore

final class StrengthSessionTests: XCTestCase {
    func testSetsAlternateWithRestAndNoRestAtTheEnd() {
        let phases = StrengthSession.phases([
            StrengthExercise(exerciseId: "squat", sets: 2, reps: 12, restS: 60),
            StrengthExercise(exerciseId: "plank", sets: 2, durationS: 40, restS: 30),
        ])
        XCTAssertEqual(phases.map(\.kind), [
            .reps(12), .rest(seconds: 60), .reps(12), .rest(seconds: 60),
            .timed(seconds: 40), .rest(seconds: 30), .timed(seconds: 40),
        ])
        XCTAssertEqual(phases.map(\.set), [1, 1, 2, 2, 1, 1, 2])
        XCTAssertEqual(phases.last?.exerciseId, "plank")
    }

    func testEmptySessionHasNoPhase() {
        XCTAssertTrue(StrengthSession.phases([]).isEmpty)
    }
}
