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

    func testPoseInterpolatesBetweenSamples() {
        let north = line(dLat: 0.0001, dLon: 0)
        // 10 points : la fraction 0,5 / 9 tombe à mi-chemin entre le 1er et le 2e relevé.
        let pose = north.pose(at: 0.5 / 9)
        XCTAssertEqual(pose.lat, 48.00005, accuracy: 1e-9)
        XCTAssertEqual(pose.lon, 2, accuracy: 1e-9)
        XCTAssertEqual(pose.heading, 0, accuracy: 0.5)
        XCTAssertEqual(north.pose(at: -1).lat, 48, accuracy: 1e-9)
        XCTAssertEqual(north.pose(at: 2).lat, 48.0009, accuracy: 1e-9)
    }

    func testSmoothingRemovesGPSZigzagAndKeepsEnds() {
        // Ligne droite vers l'est, un relevé tous les 3 m, alternativement 3 m au nord et 3 m au sud.
        let n = 200
        let mPerDegLat = 111_320.0
        let dist = (0..<n).map { Double($0) * 3 }
        let lat = (0..<n).map { 48 + ($0 % 2 == 0 ? 3.0 : -3.0) / mPerDegLat }
        let lon = dist.map { 2 + $0 / (mPerDegLat * cos(48 * .pi / 180)) }
        let track = Track(t: dist, lat: lat, lon: lon, dist: dist)
        let smooth = track.smoothed(windowM: 10)

        XCTAssertEqual(smooth.count, n)
        XCTAssertLessThan(zip(smooth.lon, track.lon).map { abs($0 - $1) }.max()!, 1e-9,
                          "seule la dérive latérale est lissée sur une ligne droite")
        XCTAssertEqual(smooth.lat[0], track.lat[0], "le départ ne bouge pas")
        XCTAssertEqual(smooth.lat[n - 1], track.lat[n - 1], "l'arrivée ne bouge pas")
        let worstMiddle = (10..<(n - 10)).map { abs(smooth.lat[$0] - 48) * mPerDegLat }.max()!
        XCTAssertLessThan(worstMiddle, 1, "écart latéral résiduel en mètres")
        XCTAssertEqual(track.smoothed(windowM: 0), track)
    }

    func testPoseHeadingCrossesNorthTheShortWay() {
        // Virage de 340° (nord-nord-ouest) à 20° (nord-nord-est) : le cap interpolé doit rester près du nord.
        var lat = [48.0], lon = [2.0]
        for i in 1..<20 {
            let bearing = (i < 10 ? 340.0 : 20.0) * .pi / 180
            lat.append(lat[i - 1] + 0.0001 * cos(bearing))
            lon.append(lon[i - 1] + 0.0001 * sin(bearing) / cos(48 * .pi / 180))
        }
        let steps = (0..<20).map { Double($0) }
        let track = Track(t: steps, lat: lat, lon: lon, dist: steps)
        for tenth in 0...10 {
            let heading = track.pose(at: Double(tenth) / 10).heading
            XCTAssertLessThan(min(heading, 360 - heading), 25, "cap \(heading) à \(tenth)/10")
        }
    }
}
