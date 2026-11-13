import XCTest
@testable import RunCoachCore

final class ReplayDirectorTests: XCTestCase {
    func testHeadingSmoothingTakesShortestPathAndConverges() {
        let step = ReplayDirector.smoothHeading(350, toward: 10, dt: 0.1)
        XCTAssertTrue(step > 350 || step < 10, "passe par le nord, pas par le sud : \(step)")
        XCTAssertEqual(ReplayDirector.smoothHeading(350, toward: 10, dt: 10), 10, accuracy: 0.01)
        XCTAssertEqual(ReplayDirector.smoothHeading(90, toward: 90, dt: 0.1), 90, accuracy: 1e-9)
        XCTAssertEqual(ReplayDirector.smoothHeading(10, toward: 350, dt: 0), 10, accuracy: 1e-9, "sans temps écoulé, rien ne bouge")
    }

    func testPointsBehindTheTiltedCameraAreDiscarded() {
        func visible(northM: Double, pitch: Double) -> Bool {
            ReplayDirector.isInFrontOfCamera(lat: 48 + northM / 111_320, lon: 2, centerLat: 48, centerLon: 2,
                                             headingDeg: 0, cameraDistanceM: 500, pitchDeg: pitch)
        }
        XCTAssertTrue(visible(northM: 1000, pitch: 60))
        XCTAssertTrue(visible(northM: -300, pitch: 60))
        XCTAssertFalse(visible(northM: -600, pitch: 60), "derrière la caméra inclinée")
        XCTAssertTrue(visible(northM: -5000, pitch: 0), "vue du dessus : rien n'est derrière")
    }

    func testPlaybackDurationIsBounded() {
        XCTAssertEqual(ReplayDirector.playbackDurationS(runDurationS: 600), 60)
        XCTAssertEqual(ReplayDirector.playbackDurationS(runDurationS: 2400), 80)
        XCTAssertEqual(ReplayDirector.playbackDurationS(runDurationS: 7200), 90)
    }

    func testDistanceLookupSkipsStopsAndInterpolates() {
        // Arrêt entre les relevés 2 et 4 : la distance ne bouge pas.
        let track = Track(t: [0, 1, 2, 3, 4, 5], lat: [0, 1, 2, 2, 2, 3], lon: [0, 0, 0, 0, 0, 0],
                          dist: [0, 10, 20, 20, 20, 30])
        XCTAssertEqual(track.index(atDistanceM: 15), 1.5, accuracy: 1e-9)
        XCTAssertEqual(track.index(atDistanceM: 20), 4, accuracy: 1e-9, "fin de l'arrêt")
        XCTAssertEqual(track.index(atDistanceM: 25), 4.5, accuracy: 1e-9)
        XCTAssertEqual(track.index(atDistanceM: -5), 0)
        XCTAssertEqual(track.index(atDistanceM: 99), 5)
        XCTAssertEqual(track.coordinate(atDistanceM: 25).lat, 2.5, accuracy: 1e-9)
    }

    func testBearingLooksAheadAndHandlesTheEnd() {
        // 100 m vers le nord, puis 100 m vers l'est.
        let lat = (0...20).map { 48 + Double(min($0, 10)) * 10 / 111_320 }
        let lon = (0...20).map { 2 + Double(max(0, $0 - 10)) * 10 / (111_320 * cos(48 * .pi / 180)) }
        let dist = (0...20).map { Double($0) * 10 }
        let track = Track(t: dist, lat: lat, lon: lon, dist: dist)
        XCTAssertEqual(track.bearing(atDistanceM: 0, aheadM: 50), 0, accuracy: 1)
        XCTAssertEqual(track.bearing(atDistanceM: 150, aheadM: 50), 90, accuracy: 1)
        XCTAssertEqual(track.bearing(atDistanceM: 200, aheadM: 50), 90, accuracy: 1, "en fin de sortie, les derniers mètres")
    }
}
