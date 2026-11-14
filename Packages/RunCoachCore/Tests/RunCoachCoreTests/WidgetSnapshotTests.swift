import XCTest
@testable import RunCoachCore

final class WidgetSnapshotTests: XCTestCase {
    func testAppGroupPrefersTheNameWrittenBySideStore() {
        XCTAssertEqual(WidgetSnapshot.appGroup(info: ["ALTAppGroups": ["group.local.runcoach.app.ABCDE12345"]]),
                       "group.local.runcoach.app.ABCDE12345")
        XCTAssertEqual(WidgetSnapshot.appGroup(info: [:]), "group.local.runcoach.app")
        XCTAssertEqual(WidgetSnapshot.appGroup(info: nil), "group.local.runcoach.app")
    }

    func testRoundTripAndProgress() throws {
        let snapshot = WidgetSnapshot(
            day: "2026-11-16",
            today: [.init(kind: .easy, title: "Footing", durationMin: 35, distanceKm: 5.2, done: false)],
            next: .init(kind: .long, title: "Sortie longue", durationMin: 60, distanceKm: 8, done: false),
            nextDay: "2026-11-22", weekDoneKm: 12, weekPlannedKm: 8)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(snapshot.weekProgress, 1, "plafonné à 100 %")
    }
}
