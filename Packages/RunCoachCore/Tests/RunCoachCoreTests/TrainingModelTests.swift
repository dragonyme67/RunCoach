import XCTest
@testable import RunCoachCore

final class TrainingModelTests: XCTestCase {
    private func day(_ key: String) -> Date { DayKey.date(key)! }

    // MARK: PaceModel

    func testReferenceAthletePaces() {
        // Utilisateur de référence (§6.3) : 5 km à 6:30/km, ressenti modéré → seuil 5:55, footing 6:58 à 7:41.
        let t = PaceModel.thresholdSPerKm(distanceM: 5000, durationS: 1950, effort: PaceModel.effort("moderate"))
        XCTAssertEqual(t, 354.5, accuracy: 0.1)
        XCTAssertEqual(PaceModel.zone(.easy, thresholdSPerKm: t), PaceRange(fastSPerKm: 418, slowSPerKm: 461))
        XCTAssertEqual(PaceModel.zone(.intervals, thresholdSPerKm: t), PaceRange(fastSPerKm: 319, slowSPerKm: 340))
        XCTAssertNil(PaceModel.zone(.strength, thresholdSPerKm: t))
        XCTAssertEqual(PaceModel.thresholdSPerKm(distanceM: 5000, durationS: 1950, effort: nil), t, "inconnu = modéré")
    }

    func testThresholdByEffort() {
        XCTAssertEqual(PaceModel.thresholdSPerKm(distanceM: 5000, durationS: 1950, effort: 3), 390 / 1.22, accuracy: 1e-9)
        // Dur : Riegel vers 10 km, 1 950 × 2^1,06 s, soit environ 404 s/km.
        XCTAssertEqual(PaceModel.thresholdSPerKm(distanceM: 5000, durationS: 1950, effort: 9), 1950 * pow(2, 1.06) / 10, accuracy: 1e-9)
    }

    func testReferenceRunIsFastestRecentOfAtLeast3Km() {
        let today = day("2026-11-13")
        let runs = [
            RunSummary(date: day("2026-11-10"), distanceM: 5000, durationS: 1950),
            RunSummary(date: day("2026-11-08"), distanceM: 2000, durationS: 600, perceivedEffort: 9),   // trop courte
            RunSummary(date: day("2026-09-01"), distanceM: 5000, durationS: 1500),                      // trop ancienne
            RunSummary(date: day("2026-11-01"), distanceM: 4000, durationS: 1520),
        ]
        XCTAssertEqual(PaceModel.referenceRun(runs, today: today)?.distanceM, 4000)
        XCTAssertNil(PaceModel.referenceRun([], today: today))
    }

    func testFeasibility() {
        let predicted = PaceModel.predictedRaceS(thresholdSPerKm: 354.5, distanceKm: 21.1)
        XCTAssertEqual(PaceModel.feasibility(predictedS: predicted, targetS: 7200), .ambitious)
        XCTAssertEqual(PaceModel.feasibility(predictedS: 7400, targetS: 7200), .onTrack)
        XCTAssertEqual(PaceModel.feasibility(predictedS: 8400, targetS: 7200), .veryAmbitious)
    }

    // MARK: LoadModel

    func testEdwardsLoad() {
        let zones = RunSummary(date: Date(), distanceM: 5000, durationS: 1800, hrZoneSeconds: [60, 600, 900, 240, 0])
        XCTAssertEqual(LoadModel.edwardsLoad(zones), 1 + 20 + 45 + 16, accuracy: 1e-9)
        let noZones = RunSummary(date: Date(), distanceM: 5000, durationS: 1800)
        XCTAssertEqual(LoadModel.edwardsLoad(noZones), 60, accuracy: 1e-9)
    }

    func testAcuteChronicRatio() {
        let today = day("2026-11-13")
        func run(_ daysAgo: Int) -> RunSummary {
            RunSummary(date: DayKey.addDays(-daysAgo, to: today), distanceM: 5000, durationS: 1800) // charge 60
        }
        let recent = LoadModel.load([run(1), run(10)], today: today)
        XCTAssertEqual(recent.acute, 60)
        XCTAssertEqual(recent.chronic, 30)
        XCTAssertNil(recent.ratio, "moins de 3 semaines de données")

        let long = LoadModel.load([run(0), run(3), run(10), run(17), run(24), run(40)], today: today)
        XCTAssertEqual(long.acute, 120)
        XCTAssertEqual(long.chronic, 75, "5 sorties sur 28 jours / 4")
        XCTAssertEqual(long.ratio ?? 0, 1.6, accuracy: 1e-9)
    }

    // MARK: MacroPlanner

    private var referenceInput: MacroPlanner.Input {
        MacroPlanner.Input(startWeek: day("2026-11-16"), raceDate: day("2027-05-16"), raceDistanceKm: 21.1,
                           v0Km: 15, l0Km: 5, availableDays: 3, beginner: true)
    }

    func testReferencePlanPhases() {
        let weeks = MacroPlanner.plan(referenceInput)
        XCTAssertEqual(weeks.count, 26)
        XCTAssertEqual(weeks.first?.weekStart, "2026-11-16")
        XCTAssertEqual(weeks.last?.weekStart, "2027-05-10")
        XCTAssertEqual(weeks.last?.phase, .race)
        XCTAssertEqual(weeks[24].phase, .taper)
        XCTAssertEqual(weeks[20...23].map(\.phase), [.peak, .peak, .peak, .peak])
        let base = weeks.filter { $0.phase == .base }
        XCTAssertGreaterThanOrEqual(base.count, 6)
        XCTAssertTrue(base.allSatisfy { $0.qualitySessions == 0 }, "débutant : pas de qualité en fondation")
        XCTAssertTrue(weeks.allSatisfy { $0.sessions >= 2 && $0.sessions <= 3 }, "3 jours disponibles")
    }

    func testReferencePlanNeverJumpsTooFast() {
        let weeks = MacroPlanner.plan(referenceInput)
        var history = [15.0, 15.0, 15.0]
        for week in weeks {
            let max3 = history.suffix(3).max()!
            XCTAssertLessThanOrEqual(week.targetKm, max(max3 * 1.10, max3 + 2) + 0.05, week.weekStart)
            XCTAssertLessThanOrEqual(week.targetKm, 38, "Vpeak = 1,8 × 21,1")
            XCTAssertLessThanOrEqual(week.longRunKm, min(0.9 * 21.1, 0.45 * week.targetKm) + 0.1, week.weekStart)
            history.append(week.targetKm)
        }
        XCTAssertEqual(weeks[3].isCutback, true)
        XCTAssertEqual(weeks[3].targetKm, (0.75 * weeks[2].targetKm * 10).rounded() / 10, accuracy: 0.11)
        XCTAssertEqual(weeks[25].longRunKm, 0, "semaine de course : pas de sortie longue en plus")
    }

    func testShortPlanAndFitnessGoal() {
        var input = referenceInput
        input.startWeek = day("2027-04-26")
        XCTAssertEqual(MacroPlanner.plan(input).map(\.phase), [.peak, .taper, .race])

        input.raceDate = nil
        let fitness = MacroPlanner.plan(input)
        XCTAssertEqual(fitness.count, 12)
        XCTAssertTrue(fitness.allSatisfy { $0.targetKm <= 22.5 + 0.05 }, "1,5 × V0")
    }
}
