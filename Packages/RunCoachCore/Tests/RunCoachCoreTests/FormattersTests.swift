import XCTest
@testable import RunCoachCore

final class FormattersTests: XCTestCase {
    func testPace() {
        XCTAssertEqual(Fmt.pace(sPerKm: 390), "6:30")
        XCTAssertEqual(Fmt.pace(sPerKm: 341), "5:41")
        XCTAssertEqual(Fmt.pace(sPerKm: 305), "5:05")
        XCTAssertEqual(Fmt.pace(sPerKm: 0), "–")
        XCTAssertEqual(Fmt.pace(speedMps: 1000.0 / 390.0), "6:30")
        XCTAssertEqual(Fmt.pace(speedMps: 0), "–")
    }

    func testDuration() {
        XCTAssertEqual(Fmt.duration(2112), "35:12")
        XCTAssertEqual(Fmt.duration(3912), "1:05:12")
        XCTAssertEqual(Fmt.duration(59), "0:59")
    }

    func testMinutes() {
        XCTAssertEqual(Fmt.minutes(45), "45 s")
        XCTAssertEqual(Fmt.minutes(600), "10 min")
        XCTAssertEqual(Fmt.minutes(3900), "1 h 05")
    }

    func testKm() {
        XCTAssertEqual(Fmt.km(5020), "5,02")
        XCTAssertEqual(Fmt.km(21097.5, decimals: 1), "21,1")
    }

    func testDayKeyRoundTrip() throws {
        let date = try XCTUnwrap(DayKey.date("2027-05-16"))
        XCTAssertEqual(DayKey.key(date), "2027-05-16")
        XCTAssertEqual(DayKey.key(DayKey.addDays(1, to: date)), "2027-05-17")
        // Le 16 mai 2027 est un dimanche : sa semaine commence le lundi 10.
        XCTAssertEqual(DayKey.key(DayKey.weekStart(date)), "2027-05-10")
    }
}
