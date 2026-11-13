import XCTest
@testable import RunCoachCore

final class HeartZonesTests: XCTestCase {
    func testZonesFollowPercentOfMax() {
        let max = 200.0
        XCTAssertEqual(HeartZones.zone(bpm: 80, maxBpm: max), 1, "sous 50 % : zone 1")
        XCTAssertEqual(HeartZones.zone(bpm: 119, maxBpm: max), 1)
        XCTAssertEqual(HeartZones.zone(bpm: 120, maxBpm: max), 2)
        XCTAssertEqual(HeartZones.zone(bpm: 150, maxBpm: max), 3)
        XCTAssertEqual(HeartZones.zone(bpm: 179, maxBpm: max), 4)
        XCTAssertEqual(HeartZones.zone(bpm: 180, maxBpm: max), 5)
        XCTAssertEqual(HeartZones.zone(bpm: 230, maxBpm: max), 5, "au-delà du max")
        XCTAssertEqual(HeartZones.zone(bpm: 150, maxBpm: 0), 1)
    }

    func testEstimatedMax() {
        XCTAssertEqual(HeartZones.estimatedMaxBpm(ageYears: 20), 194, accuracy: 1e-9)
    }
}
