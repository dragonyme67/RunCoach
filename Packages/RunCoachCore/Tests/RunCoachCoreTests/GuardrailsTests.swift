import XCTest
@testable import RunCoachCore

/// Chaque garde-fou : la semaine de référence passe, une modification ciblée le déclenche (ARCHITECTURE.md §6.4).
final class GuardrailsTests: XCTestCase {
    static let threshold = 354.5   // utilisateur de référence, §6.3

    static func snapshot(lastWeeksKm: [Double] = [15, 15, 15], longestKm: Double = 5.3) -> AthleteSnapshot {
        var paces: [String: [Int]] = [:]
        for kind in [WorkoutKind.recovery, .easy, .long, .tempo, .intervals] {
            let z = PaceModel.zone(kind, thresholdSPerKm: threshold)!
            paces[kind.rawValue] = [z.fastSPerKm, z.slowSPerKm]
        }
        return AthleteSnapshot(
            today: "2026-11-13",
            athlete: .init(age: 21, sex: nil, runningSinceWeeks: 3, level: "beginner", injuryNote: "", currentPain: false,
                           fatigueLevel: "normal", wantsStrength: true, strengthEquipment: "none"),
            goal: .init(kind: "race", distanceKm: 21.1, date: "2027-05-16"),
            pacesSPerKm: paces, hrZonesBpm: [],
            lastWeeks: lastWeeksKm.enumerated().map { .init(weekStart: "2026-10-\(19 + 7 * $0.offset)", km: $0.element, runs: 3, load: 150, longestKm: longestKm) },
            lastRuns: [], load: .init(acute: 150, chronic: 150, ratio: 1), recovery: .init(sleepHAvg7d: nil, hrvStatus: nil, restingHr: nil),
            missedLast14d: 0)
    }

    /// Exemple de WeekBrief du §6.2.
    static func brief() -> WeekBrief {
        WeekBrief(weekStart: "2026-11-16", phase: .base, isCutback: false, targetKm: 16.5, minKm: 13.2, maxKm: 17.3,
                  runSessions: 3, maxQualitySessions: 0, longRunKm: [6, 7], longRunDay: "2026-11-22",
                  availableDays: ["2026-11-17", "2026-11-19", "2026-11-22"], maxSessionMin: 60,
                  strengthSessions: 1, strengthDays: ["2026-11-18", "2026-11-20"], allowedKinds: [.easy, .long, .recovery, .strength])
    }

    static func easy(_ date: String, minutes: Double, target: WorkoutTarget = .pace(418, 461)) -> WorkoutSpec {
        WorkoutSpec(date: date, kind: .easy, title: "Footing", rationale: "", estimatedDurationMin: 0, estimatedDistanceKm: nil,
                    blocks: [WorkoutBlock(steps: [WorkoutStep(intent: .run, end: .time, value: minutes * 60, target: target)])])
    }

    static func tempo(_ date: String, repMin: Double, reps: Int = 2) -> WorkoutSpec {
        WorkoutSpec(date: date, kind: .tempo, title: "Tempo", rationale: "", estimatedDurationMin: 0, estimatedDistanceKm: nil, blocks: [
            WorkoutBlock(steps: [WorkoutStep(intent: .warmup, end: .time, value: 600)]),
            WorkoutBlock(repeatCount: reps, steps: [
                WorkoutStep(intent: .run, end: .time, value: repMin * 60, target: .pace(355, 372)),
                WorkoutStep(intent: .recover, end: .time, value: 120),
            ]),
            WorkoutBlock(steps: [WorkoutStep(intent: .cooldown, end: .time, value: 600)]),
        ])
    }

    static func week() -> [WorkoutSpec] {
        [
            easy("2026-11-17", minutes: 40),
            WorkoutSpec(date: "2026-11-18", kind: .strength, title: "Renfo", rationale: "", estimatedDurationMin: 0, estimatedDistanceKm: nil,
                        exercises: [StrengthExercise(exerciseId: "squat", sets: 3, reps: 12, restS: 60),
                                    StrengthExercise(exerciseId: "plank", sets: 3, durationS: 40, restS: 45)]),
            easy("2026-11-19", minutes: 35),
            WorkoutSpec(date: "2026-11-22", kind: .long, title: "Sortie longue", rationale: "", estimatedDurationMin: 0, estimatedDistanceKm: nil,
                        blocks: [WorkoutBlock(steps: [WorkoutStep(intent: .run, end: .distance, value: 6500, target: .pace(418, 468))])]),
        ]
    }

    private func rules(_ week: [WorkoutSpec], brief: WeekBrief = brief(), snapshot: AthleteSnapshot = snapshot()) -> Set<String> {
        Set(Guardrails.validate(week: week, brief: brief, snapshot: snapshot).map(\.rule))
    }

    func testReferenceWeekPasses() {
        XCTAssertEqual(Guardrails.validate(week: Self.week(), brief: Self.brief(), snapshot: Self.snapshot()), [])
    }

    func testDistanceIsRecomputedFromBlocks() {
        let w = Self.week()
        XCTAssertEqual(Guardrails.distanceKm(w[0], easyPaceSPerKm: 439.5), 40 * 60 / 439.5, accuracy: 1e-9)
        XCTAssertEqual(Guardrails.distanceKm(w[3], easyPaceSPerKm: 439.5), 6.5, accuracy: 1e-9)
        XCTAssertEqual(Guardrails.distanceKm(w[1], easyPaceSPerKm: 439.5), 0)
    }

    func testG1WeekAboveBriefMax() {
        var brief = Self.brief()
        brief.maxKm = 16
        XCTAssertEqual(rules(Self.week(), brief: brief), ["G1"])
    }

    func testG2JumpAboveRecentWeeks() {
        XCTAssertEqual(rules(Self.week(), snapshot: Self.snapshot(lastWeeksKm: [12, 12, 12])), ["G2"])
    }

    func testG3LongRunTooLong() {
        var brief = Self.brief()
        brief.longRunKm = [5, 6]
        XCTAssertEqual(rules(Self.week(), brief: brief), ["G3"])
        XCTAssertTrue(rules(Self.week(), snapshot: Self.snapshot(longestKm: 4)).contains("G3"), "plus longue récente + 2 km")
    }

    func testG4TooManyQualitySessions() {
        var week = Self.week()
        week[0] = Self.tempo("2026-11-17", repMin: 5)
        XCTAssertTrue(rules(week).contains("G4"))
    }

    func testG5ConsecutiveHardDays() {
        var brief = Self.brief()
        brief.availableDays.append("2026-11-21")
        brief.maxQualitySessions = 1
        brief.allowedKinds += [.tempo]
        var week = Self.week()
        week[2] = Self.tempo("2026-11-21", repMin: 5)
        XCTAssertEqual(rules(week, brief: brief), ["G5"])
    }

    func testG6NotEnoughRestDays() {
        var brief = Self.brief()
        brief.availableDays = (16...22).map { "2026-11-\($0)" }
        let week = Self.week() + [Self.easy("2026-11-16", minutes: 10), Self.easy("2026-11-20", minutes: 10)]
        XCTAssertTrue(rules(week, brief: brief).contains("G6"))
    }

    func testG7RunOnUnavailableDay() {
        var week = Self.week()
        week[0].date = "2026-11-16"
        XCTAssertEqual(rules(week), ["G7"])
    }

    func testG8SessionTooLong() {
        var week = Self.week()
        week[0] = Self.easy("2026-11-17", minutes: 70)
        XCTAssertTrue(rules(week).contains("G8"))
    }

    func testG9PaceOutsideZone() {
        var week = Self.week()
        week[0] = Self.easy("2026-11-17", minutes: 35, target: .pace(380, 400))
        XCTAssertEqual(rules(week), ["G9"])
    }

    /// Glisser-déposer d'une séance (étape 7) : mêmes vérifications que les actions du chat.
    func testDragAndDropMoveIsChecked() {
        func check(_ from: String, _ to: String) -> [String] {
            CoachEngine.checkActions([PlanAction(op: .move, date: from, newDate: to)], planned: Self.week(),
                                     briefs: [Self.brief()], snapshot: Self.snapshot(), todayKey: "2026-11-16").problems
        }
        XCTAssertEqual(check("2026-11-19", "2026-11-20"), [], "un footing déplacé au vendredi : permis")
        XCTAssertTrue(check("2026-11-18", "2026-11-21").contains { $0.hasPrefix("G13") }, "renfo la veille de la sortie longue")
        XCTAssertFalse(check("2026-11-22", "2026-11-23").isEmpty, "semaine suivante sans plan")
    }

    /// Plus lent que la zone, et course/marche (4 min / 1 min) : permis (demande du 2026-11-14).
    func testG9AllowsSlowerPaceAndRunWalk() {
        var week = Self.week()
        week[0] = Self.easy("2026-11-17", minutes: 35, target: .pace(480, 540))
        week[1] = WorkoutSpec(date: week[1].date, kind: .easy, title: "Course/marche", rationale: "r",
                              estimatedDurationMin: 30, estimatedDistanceKm: nil,
                              blocks: [WorkoutBlock(repeatCount: 6, steps: [
                                  WorkoutStep(intent: .run, end: .time, value: 240, target: .pace(440, 470)),
                                  WorkoutStep(intent: .rest, end: .time, value: 60, note: "Marche"),
                              ])])
        XCTAssertFalse(rules(week).contains("G9"))
    }

    func testG10TooMuchFastRunning() {
        var brief = Self.brief()
        brief.maxQualitySessions = 1
        brief.allowedKinds += [.tempo]
        var week = Self.week()
        week[0] = Self.tempo("2026-11-17", repMin: 12, reps: 3)
        XCTAssertTrue(rules(week, brief: brief).contains("G10"))
        week[0] = Self.tempo("2026-11-17", repMin: 5)
        XCTAssertFalse(rules(week, brief: brief).contains("G10"), "2 × 5 min au seuil : moins de 2 km")
    }

    func testG11PainAndFatigue() {
        var pain = Self.snapshot()
        pain.athlete.currentPain = true
        XCTAssertTrue(rules(Self.week(), snapshot: pain).contains("G11"))
        let recovery = WorkoutSpec(date: "2026-11-17", kind: .recovery, title: "Récup", rationale: "", estimatedDurationMin: 0,
                                   estimatedDistanceKm: nil, blocks: [WorkoutBlock(steps: [WorkoutStep(intent: .run, end: .time, value: 1500)])])
        XCTAssertFalse(rules([recovery], snapshot: pain).contains("G11"), "25 min de récupération restent permises")

        var tired = Self.snapshot()
        tired.athlete.fatigueLevel = "high"
        XCTAssertTrue(rules(Self.week(), snapshot: tired).contains("G11"), "16,7 km > 80 % de 16,5")
    }

    func testG12Structure() {
        var week = Self.week()
        week[0].blocks[0].repeatCount = 0
        XCTAssertEqual(rules(week), ["G12"])
        week = Self.week()
        week[1].exercises[0].exerciseId = "burpee"
        XCTAssertEqual(rules(week), ["G12"])

        var brief = Self.brief()
        brief.maxQualitySessions = 1
        brief.allowedKinds += [.tempo]
        week = Self.week()
        week[0] = Self.tempo("2026-11-17", repMin: 5)
        week[0].blocks.removeFirst()
        XCTAssertEqual(rules(week, brief: brief), ["G12"], "tempo sans échauffement")
    }

    func testG13StrengthBeforeHardDay() {
        var week = Self.week()
        week[1].date = "2026-11-21"
        XCTAssertEqual(rules(week), ["G13"])
    }

    // MARK: - Plan de secours

    /// 26 semaines simulées : l'athlète court exactement le plan de secours, qui doit passer tous les garde-fous.
    func testFallbackPassesAllGuardrailsOver26Weeks() {
        let macro = MacroPlanner.plan(MacroPlanner.Input(startWeek: DayKey.date("2026-11-16")!, raceDate: DayKey.date("2027-05-16")!,
                                                         raceDistanceKm: 21.1, v0Km: 15, l0Km: 5, availableDays: 3, beginner: true))
        XCTAssertEqual(macro.count, 26)
        var history: [(km: Double, longest: Double)] = [(15, 5), (15, 5), (15, 5)]
        for (i, week) in macro.enumerated() {
            let raceDay = i == macro.count - 1 ? "2027-05-16" : nil
            let brief = WeekBriefBuilder.brief(.init(week: week, availableWeekdays: [2, 4, 7], longRunWeekday: 7, maxSessionMin: 60,
                                                     wantsStrength: true, beginner: true, loadRatio: nil,
                                                     lastWeekKm: history.last!.km, raceDay: raceDay))
            var snapshot = Self.snapshot()
            snapshot.lastWeeks = history.suffix(3).map { .init(weekStart: "", km: $0.km, runs: 3, load: 0, longestKm: $0.longest) }
            for fatigue in ["normal", "high"] {
                snapshot.athlete.fatigueLevel = fatigue
                let plan = FallbackPlanner.week(brief: brief, snapshot: snapshot, raceDay: raceDay, raceDistanceKm: 21.1)
                let violations = Guardrails.validate(week: plan, brief: brief, snapshot: snapshot)
                XCTAssertEqual(violations, [], "\(week.weekStart) \(fatigue)")
                XCTAssertFalse(plan.isEmpty, week.weekStart)
            }
            snapshot.athlete.fatigueLevel = "normal"
            let plan = FallbackPlanner.week(brief: brief, snapshot: snapshot, raceDay: raceDay, raceDistanceKm: 21.1)
            let runs = plan.filter { $0.kind.isRun && $0.kind != .race }
            let km = runs.reduce(0) { $0 + Guardrails.distanceKm($1, easyPaceSPerKm: Guardrails.easyPaceSPerKm(snapshot)) }
            if i == macro.count - 1 { XCTAssertTrue(plan.contains { $0.kind == .race && $0.date == "2027-05-16" }) }
            history.append((km, runs.filter { $0.kind == .long }.map { Guardrails.distanceKm($0, easyPaceSPerKm: 0) }.max() ?? 0))
        }
        XCTAssertGreaterThan(history.map(\.km).max()!, 25, "le volume progresse vraiment")
    }

    func testFallbackRestsWhenInPain() {
        var pain = Self.snapshot()
        pain.athlete.currentPain = true
        XCTAssertEqual(FallbackPlanner.week(brief: Self.brief(), snapshot: pain), [])
    }
}
