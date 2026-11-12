import XCTest
@testable import RunCoachCore

final class TrackTests: XCTestCase {
    /// Tracé rectiligne de 10 points partant de (48, 2) avec un pas donné en degrés.
    private func line(dLat: Double, dLon: Double) -> Track {
        let steps = (0..<10).map { Double($0) }
        return Track(t: steps, lat: steps.map { 48 + $0 * dLat }, lon: steps.map { 2 + $0 * dLon }, dist: steps)
    }

    func testHeadingFollowsDirectionOfTravel() {
        XCTAssertEqual(line(dLat: 0.0001, dLon: 0).heading(at: 5), 0, accuracy: 0.5)
        XCTAssertEqual(line(dLat: 0, dLon: 0.0001).heading(at: 5), 90, accuracy: 0.5)
        XCTAssertEqual(line(dLat: -0.0001, dLon: 0).heading(at: 5), 180, accuracy: 0.5)
        XCTAssertEqual(line(dLat: 0, dLon: -0.0001).heading(at: 5), 270, accuracy: 0.5)
    }

    func testHeadingAtEndsAndOutOfRange() {
        let east = line(dLat: 0, dLon: 0.0001)
        XCTAssertEqual(east.heading(at: 0), 90, accuracy: 0.5)
        XCTAssertEqual(east.heading(at: 9), 90, accuracy: 0.5)
        XCTAssertEqual(east.heading(at: 500), 90, accuracy: 0.5)
        XCTAssertEqual(Track(t: [0], lat: [48], lon: [2], dist: [0]).heading(at: 0), 0)
    }
}
