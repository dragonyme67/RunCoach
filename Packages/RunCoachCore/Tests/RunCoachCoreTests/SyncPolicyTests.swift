import XCTest
@testable import RunCoachCore

final class SyncPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRateLimitBackoffDoublesAndCapsAtOneDay() {
        let minutes = (0...8).map { failures in
            SyncPolicy.nextAllowedCall(after: .rateLimited, failures: failures, now: now)!.timeIntervalSince(now) / 60
        }
        XCTAssertEqual(minutes, [15, 30, 60, 120, 240, 480, 960, 1440, 1440])
    }

    func testBlockedWaitsOneHourAndOtherErrorsDoNotWait() {
        XCTAssertEqual(SyncPolicy.nextAllowedCall(after: .blocked, failures: 5, now: now), now.addingTimeInterval(3600))
        for error in [GarminError.network, .decoding, .needsLogin, .http(500)] {
            XCTAssertNil(SyncPolicy.nextAllowedCall(after: error, failures: 0, now: now))
        }
    }

    func testBudget() {
        XCTAssertEqual(SyncPolicy.budget(background: false, backfillDone: false), Int.max)
        XCTAssertEqual(SyncPolicy.budget(background: false, backfillDone: true), 40)
        XCTAssertEqual(SyncPolicy.budget(background: true, backfillDone: false), 20)
    }

    func testMetricDaysAlwaysRefreshTodayAndYesterdayThenFillGaps() {
        let today = DayKey.date("2026-11-13")!
        let all = SyncPolicy.metricDays(today: today, existing: [])
        XCTAssertEqual(all.count, 28)
        XCTAssertEqual(all.prefix(3), ["2026-11-13", "2026-11-12", "2026-11-11"])
        XCTAssertEqual(all.last, "2026-10-17")

        let existing = Set(all.filter { $0 != "2026-11-01" })
        XCTAssertEqual(SyncPolicy.metricDays(today: today, existing: existing), ["2026-11-13", "2026-11-12", "2026-11-01"])
    }

    func testKmSplitsInterpolateBoundaries() {
        // 2,5 km à 4 m/s, un relevé toutes les 10 s ; FC 140 puis 160 après 1 000 m ; on monte de 1 m par relevé.
        let t = (0...63).map { Double($0) * 10 }
        let dist = t.map { min($0 * 4, 2500) }
        let track = Track(t: t, lat: t.map { _ in 0 }, lon: t.map { _ in 0 }, dist: dist,
                          ele: t.indices.map(Double.init), hr: dist.map { $0 < 1000 ? 140 : 160 })
        let splits = track.kmSplits()
        XCTAssertEqual(splits.map(\.index), [1, 2, 3])
        XCTAssertEqual(splits.map(\.distanceM), [1000, 1000, 500])
        XCTAssertEqual(splits[0].durationS, 250, accuracy: 1e-9)
        XCTAssertEqual(splits[1].durationS, 250, accuracy: 1e-9)
        XCTAssertEqual(splits[0].avgSpeedMps!, 4, accuracy: 1e-9)
        XCTAssertEqual(splits[1].avgHR, 160)
        XCTAssertEqual(splits[0].elevationGainM!, 25, accuracy: 1e-9)
        XCTAssertEqual(splits[0].elevationLossM, 0)
    }

    func testKmSplitsDropTinyRemainder() {
        let track = Track(t: [0, 300, 310], lat: [0, 0, 0], lon: [0, 0, 0], dist: [0, 1000, 1030])
        XCTAssertEqual(track.kmSplits().map(\.distanceM), [1000])
        XCTAssertEqual(Track(t: [0], lat: [0], lon: [0], dist: [0]).kmSplits(), [])
    }
}
