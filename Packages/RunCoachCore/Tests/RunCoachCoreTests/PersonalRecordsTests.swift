import XCTest
@testable import RunCoachCore

final class PersonalRecordsTests: XCTestCase {
    /// Sortie synthétique : 1 relevé par seconde, 3 m/s, sauf un passage à 5 m/s entre 2 000 et 3 000 m.
    private func track() -> Track {
        var t: [Double] = [0], dist: [Double] = [0]
        while dist.last! < 6000 {
            let speed = (2000..<3000).contains(dist.last!) ? 5.0 : 3.0
            t.append(t.last! + 1)
            dist.append(dist.last! + speed)
        }
        return Track(t: t, lat: t.map { _ in 0 }, lon: t.map { _ in 0 }, dist: dist)
    }

    func testBestKilometreIsTheFastestStretch() throws {
        let best = try XCTUnwrap(PersonalRecords.bestEffortS(track(), distanceM: 1000))
        XCTAssertEqual(best, 200, accuracy: 1, "1 000 m à 5 m/s")
    }

    func testBestFiveKilometresMixesBothPaces() throws {
        // 1 000 m à 5 m/s (200 s) et 4 000 m à 3 m/s (1 333 s).
        let best = try XCTUnwrap(PersonalRecords.bestEffortS(track(), distanceM: 5000))
        XCTAssertEqual(best, 1533, accuracy: 2)
    }

    func testTooShortRunHasNoEffort() {
        XCTAssertNil(PersonalRecords.bestEffortS(track(), distanceM: 10000))
    }

    func testRecordComparison() {
        XCTAssertTrue(PersonalRecords.isRecord(290, previous: [300, 310]))
        XCTAssertFalse(PersonalRecords.isRecord(305, previous: [300, 310]))
        XCTAssertTrue(PersonalRecords.isRecord(300, previous: []), "première sortie : record")
        XCTAssertTrue(PersonalRecords.isRecord(21.1, previous: [15, 18], higherIsBetter: true))
        XCTAssertFalse(PersonalRecords.isRecord(nil, previous: []))
    }
}
