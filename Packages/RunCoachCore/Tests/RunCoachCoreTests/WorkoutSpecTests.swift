import XCTest
@testable import RunCoachCore

final class WorkoutSpecTests: XCTestCase {
    /// Exemple de référence de ARCHITECTURE.md §5.3.1.
    static let intervalsJSON = """
    {
      "date": "2026-11-18", "kind": "intervals", "title": "Fractionné court 6 × 400 m",
      "rationale": "Première séance de vitesse.",
      "estimated_duration_min": 40, "estimated_distance_km": 6.0,
      "blocks": [
        { "repeat": 1, "steps": [
          { "intent": "warmup", "end": "time", "value": 600,
            "target": { "type": "none", "min_s_per_km": null, "max_s_per_km": null, "hr_zone": null },
            "note": "Très facile" } ] },
        { "repeat": 6, "steps": [
          { "intent": "run", "end": "distance", "value": 400,
            "target": { "type": "pace", "min_s_per_km": 325, "max_s_per_km": 340, "hr_zone": null },
            "note": null },
          { "intent": "recover", "end": "time", "value": 90,
            "target": { "type": "none", "min_s_per_km": null, "max_s_per_km": null, "hr_zone": null },
            "note": "Marche ou trot" } ] },
        { "repeat": 1, "steps": [
          { "intent": "cooldown", "end": "time", "value": 600,
            "target": { "type": "none", "min_s_per_km": null, "max_s_per_km": null, "hr_zone": null },
            "note": null } ] }
      ],
      "exercises": []
    }
    """

    func testDecodesReferenceExample() throws {
        let spec = try JSONDecoder().decode(WorkoutSpec.self, from: Data(Self.intervalsJSON.utf8))
        XCTAssertEqual(spec.kind, .intervals)
        XCTAssertEqual(spec.blocks.count, 3)
        XCTAssertEqual(spec.blocks[1].repeatCount, 6)
        XCTAssertEqual(spec.blocks[1].steps[0].target, .pace(325, 340))
        XCTAssertEqual(spec.blocks[1].steps[0].target.label, "5:25–5:40 /km")
        XCTAssertEqual(spec.blocks[1].steps[0].lengthLabel, "400 m")
        XCTAssertEqual(spec.blocks[0].steps[0].lengthLabel, "10 min")
        XCTAssertNil(spec.blocks[0].steps[0].target.label)
    }

    func testSegmentsUnrollRepeats() throws {
        let spec = try JSONDecoder().decode(WorkoutSpec.self, from: Data(Self.intervalsJSON.utf8))
        let segments = spec.segments(easyPaceSPerKm: 420)
        XCTAssertEqual(segments.count, 14)
        XCTAssertEqual(segments.filter { $0.isFast }.count, 6)
        // 600 + 6 × (0,4 km × 332,5 s/km + 90) + 600
        let total = segments.reduce(0) { $0 + $1.seconds }
        XCTAssertEqual(total, 2538, accuracy: 0.5)
    }

    func testRoundTrip() throws {
        let spec = WorkoutSpec(
            date: "2026-11-20", kind: .strength, title: "Renfo coureur", rationale: "Gainage et fessiers.",
            estimatedDurationMin: 25, estimatedDistanceKm: nil,
            exercises: [StrengthExercise(exerciseId: "squat", sets: 3, reps: 12, restS: 60)]
        )
        let data = try JSONEncoder().encode(spec)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutSpec.self, from: data), spec)
    }

    func testTrackConsistency() {
        var track = Track(t: [0, 5], lat: [48.0, 48.1], lon: [2.0, 2.1], dist: [0, 15], hr: [140, 142])
        XCTAssertTrue(track.isConsistent)
        track.hr = [140]
        XCTAssertFalse(track.isConsistent)
    }
}
