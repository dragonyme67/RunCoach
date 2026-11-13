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

    func testBlendJoinsBothCamerasSmoothly() {
        let overview = ReplayCamera(centerLat: 48, centerLon: 2, distanceM: 4000, pitchDeg: 0, headingDeg: 350)
        let follow = ReplayCamera(centerLat: 48.01, centerLon: 2.01, distanceM: 500, pitchDeg: 60, headingDeg: 20)
        XCTAssertEqual(ReplayDirector.blend(overview, follow, t: 0), overview)
        let end = ReplayDirector.blend(overview, follow, t: 1)
        XCTAssertEqual(end.distanceM, 500, accuracy: 1e-6)
        XCTAssertEqual(end.headingDeg, 20, accuracy: 1e-6)
        XCTAssertEqual(end.centerLat, 48.01, accuracy: 1e-12)
        let mid = ReplayDirector.blend(overview, follow, t: 0.5)
        XCTAssertEqual(mid.distanceM, 1414.2, accuracy: 0.1, "moyenne géométrique de 4 000 et 500")
        XCTAssertEqual(mid.headingDeg, 5, accuracy: 1e-6, "de 350° à 20° en passant par le nord")
        XCTAssertEqual(mid.pitchDeg, 30, accuracy: 1e-6)
        XCTAssertEqual(ReplayDirector.blend(overview, follow, t: 7), end, "borné à 1")
    }

    func testOverviewFramesTheWholeTrack() {
        // 2 km vers le nord.
        let track = Track(t: [0, 1], lat: [48, 48 + 2000 / 111_320], lon: [2, 2], dist: [0, 2000])
        let camera = ReplayDirector.overview(of: track, viewAspect: 0.5)
        XCTAssertEqual(camera.centerLat, 48 + 1000 / 111_320, accuracy: 1e-9)
        XCTAssertEqual(camera.distanceM, 5200, accuracy: 1)
        XCTAssertEqual(camera.pitchDeg, 0)
        XCTAssertEqual(camera.headingDeg, 0)
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
        let degLat: Double = 10 / 111_320
        let degLon: Double = degLat / cos(48 * Double.pi / 180)
        let lat: [Double] = (0...20).map { i in 48 + Double(min(i, 10)) * degLat }
        let lon: [Double] = (0...20).map { i in 2 + Double(max(0, i - 10)) * degLon }
        let dist = (0...20).map { Double($0) * 10 }
        let track = Track(t: dist, lat: lat, lon: lon, dist: dist)
        XCTAssertEqual(track.bearing(atDistanceM: 0, aheadM: 50), 0, accuracy: 1)
        XCTAssertEqual(track.bearing(atDistanceM: 150, aheadM: 50), 90, accuracy: 1)
        XCTAssertEqual(track.bearing(atDistanceM: 200, aheadM: 50), 90, accuracy: 1, "en fin de sortie, les derniers mètres")
    }
}
