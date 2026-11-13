import XCTest
@testable import RunCoachCore

/// Étape 4.7 et actions du chat : rattachement réalisé/prévu, modifications validées, semaine de course, recalcul du plan.
final class PlanFlowTests: XCTestCase {
    // MARK: WorkoutMatcher

    func testMatcherLinksSameDaySameKindAndMarksMissed() {
        let planned = [
            WorkoutMatcher.Planned(dayKey: "2026-11-17", isRun: true, status: "planned"),
            WorkoutMatcher.Planned(dayKey: "2026-11-18", isRun: false, status: "planned"),
            WorkoutMatcher.Planned(dayKey: "2026-11-19", isRun: true, status: "planned"),
            WorkoutMatcher.Planned(dayKey: "2026-11-20", isRun: true, status: "planned"),
            WorkoutMatcher.Planned(dayKey: "2026-11-16", isRun: true, status: "done"),
        ]
        let done = [
            WorkoutMatcher.Done(dayKey: "2026-11-17", isRun: true),
            WorkoutMatcher.Done(dayKey: "2026-11-18", isRun: true),   // course un jour de renfo : pas de rattachement
        ]
        let result = WorkoutMatcher.match(planned: planned, done: done, todayKey: "2026-11-20")
        XCTAssertEqual(result.pairs.map(\.planned), [0])
        XCTAssertEqual(result.pairs.map(\.done), [0])
        XCTAssertEqual(result.missed, [1, 2], "le 20 n'est pas fini ; le 16 est déjà fait")
    }

    // MARK: PlanActions

    func testActionsApplyToACopy() {
        let week = GuardrailsTests.week()
        let recovery = WorkoutSpec(date: "x", kind: .recovery, title: "Récup", rationale: "", estimatedDurationMin: 0, estimatedDistanceKm: nil,
                                   blocks: [WorkoutBlock(steps: [WorkoutStep(intent: .run, end: .time, value: 1500, target: .pace(461, 514))])])
        let outcome = PlanActions.apply([
            PlanAction(op: .replace, date: "2026-11-19", workout: recovery),
            PlanAction(op: .move, date: "2026-11-18", newDate: "2026-11-20"),
            PlanAction(op: .remove, date: "2026-11-21"),
            PlanAction(op: .add, date: "2026-11-10", workout: recovery),
        ], to: week, todayKey: "2026-11-16")
        XCTAssertEqual(outcome.specs.first { $0.date == "2026-11-19" }?.kind, .recovery)
        XCTAssertEqual(outcome.specs.first { $0.kind == .strength }?.date, "2026-11-20")
        XCTAssertEqual(outcome.lines.count, 2)
        XCTAssertEqual(outcome.problems.count, 2, "aucune séance le 21 ; le 10 est passé")
        XCTAssertEqual(week[2].kind, .easy, "l'original n'est pas touché")
    }

    // MARK: Chat avec actions

    private final class Queue: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [HTTPResponse]
        init(_ items: [HTTPResponse]) { self.items = items }
        func next() -> HTTPResponse { lock.lock(); defer { lock.unlock() }; return items.count > 1 ? items.removeFirst() : items[0] }
    }

    private func reply(_ actions: [PlanAction]) -> HTTPResponse {
        let text = String(decoding: try! JSONEncoder().encode(ChatResponse(reply: "Je te propose ceci.", actions: actions)), as: UTF8.self)
        return HTTPResponse(status: 200, body: try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text]]]]))
    }

    private func chat(_ responses: [HTTPResponse]) async throws -> (CoachEngine.ChatOutcome, FakeHTTP) {
        let queue = Queue(responses)
        let http = FakeHTTP { _ in queue.next() }
        let outcome = try await CoachEngine.chat(
            llm: LLMClient(http: http, provider: .groq, apiKey: "k"), todayLabel: "lundi 16 novembre 2026", todayKey: "2026-11-16",
            snapshot: GuardrailsTests.snapshot(), upcoming: "[]", planned: GuardrailsTests.week(), briefs: [GuardrailsTests.brief()],
            history: [], message: "Remplace ma séance de jeudi par quelque chose de plus léger")
        return (outcome, http)
    }

    private var recoveryThursday: PlanAction {
        PlanAction(op: .replace, date: "2026-11-19", workout: WorkoutSpec(
            date: "2026-11-19", kind: .recovery, title: "Récupération", rationale: "Jambes lourdes : on récupère.",
            estimatedDurationMin: 25, estimatedDistanceKm: nil,
            blocks: [WorkoutBlock(steps: [WorkoutStep(intent: .run, end: .time, value: 1500, target: .pace(461, 514))])]))
    }

    func testValidActionsAreKeptWithLines() async throws {
        let (outcome, http) = try await chat([reply([recoveryThursday])])
        XCTAssertEqual(outcome.response.actions.count, 1)
        XCTAssertEqual(outcome.actionLines.count, 1)
        XCTAssertEqual(http.requests.count, 1)
        let body = (try JSONSerialization.jsonObject(with: http.requests[0].body!)) as! [String: Any]
        let schema = ((body["response_format"] as! [String: Any])["json_schema"] as! [String: Any])["schema"] as! [String: Any]
        XCTAssertNotNil((schema["properties"] as! [String: Any])["actions"], "question d'entraînement : schéma avec actions")
    }

    func testExplicitRequestsMayLeaveUsualDaysAndAddStrength() async throws {
        let monday = PlanAction(op: .move, date: "2026-11-17", newDate: "2026-11-16")   // lundi : hors des jours habituels
        let strength = PlanAction(op: .add, date: "2026-11-20", workout: GuardrailsTests.week()[1])
        let (outcome, http) = try await chat([reply([monday, strength])])
        XCTAssertEqual(outcome.response.actions.count, 2, "demande explicite : les préférences ne bloquent pas")
        XCTAssertEqual(outcome.actionLines.count, 2)
        XCTAssertEqual(http.requests.count, 1)
    }

    func testInvalidActionsAreRepairedOnceThenDropped() async throws {
        // G4 : aucune séance de qualité autorisée cette semaine (débutant en fondation).
        let monday = PlanAction(op: .replace, date: "2026-11-17", workout: GuardrailsTests.tempo("2026-11-17", repMin: 5))
        let (repaired, http) = try await chat([reply([monday]), reply([recoveryThursday])])
        XCTAssertEqual(repaired.response.actions, [recoveryThursday].map { action in
            var a = action
            a.workout = a.workout.map { CoachEngine.normalized($0, easyPaceSPerKm: 439.5) }
            return a
        })
        XCTAssertEqual(http.requests.count, 2)

        let (dropped, _) = try await chat([reply([monday])])
        XCTAssertEqual(dropped.response.actions, [])
        XCTAssertEqual(dropped.actionLines, [])
        XCTAssertTrue(dropped.response.reply.contains("règle de sécurité"))
        XCTAssertFalse(dropped.response.reply.contains("G4"), "raison lisible, sans identifiant de règle")
    }

    // MARK: Semaine de course, recalcul

    func testRaceDayIsPlacedByCodeEvenWithAI() async {
        var brief = GuardrailsTests.brief()
        brief.allowedKinds.append(.race)
        let aiWeek = GuardrailsTests.week() + [WorkoutSpec(date: "2026-11-21", kind: .race, title: "Course inventée", rationale: "",
                                                          estimatedDurationMin: 0, estimatedDistanceKm: nil,
                                                          blocks: [WorkoutBlock(steps: [WorkoutStep(intent: .run, end: .distance, value: 5000)])])]
        let text = String(decoding: try! JSONEncoder().encode(WeekPlanResponse(weekStart: "2026-11-16", summary: "", workouts: aiWeek)), as: UTF8.self)
        let http = FakeHTTP { _ in HTTPResponse(status: 200, body: try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text]]]])) }
        brief.longRunDay = nil
        let result = await CoachEngine.generateWeek(llm: LLMClient(http: http, provider: .groq, apiKey: "k"), snapshot: GuardrailsTests.snapshot(),
                                                    brief: brief, recentPlan: "[]", raceDay: "2026-11-22", raceDistanceKm: 21.1)
        let races = result.workouts.filter { $0.kind == .race }
        XCTAssertEqual(races.map(\.date), ["2026-11-22"], "la course de l'IA est remplacée par celle du code")
        XCTAssertEqual(races.first?.estimatedDistanceKm, 21.1)
    }

    func testCutbackCadenceSurvivesWeeklyRecalculation() {
        let input = MacroPlanner.Input(startWeek: DayKey.date("2026-11-30")!, raceDate: DayKey.date("2027-05-16")!, raceDistanceKm: 21.1,
                                       v0Km: 18, l0Km: 6, availableDays: 3, beginner: true, cycleOffset: 2)
        let weeks = MacroPlanner.plan(input)
        XCTAssertEqual(weeks[1].isCutback, true, "2 semaines déjà faites : l'allègement tombe à la 4e semaine depuis le début")
        XCTAssertEqual(weeks[0].isCutback, false)
    }
}
