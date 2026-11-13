import XCTest
@testable import RunCoachCore

/// Client IA et moteur du coach, contre un serveur simulé : aucun test n'appelle un vrai fournisseur.
final class CoachTests: XCTestCase {
    private static func completion(_ content: String) -> HTTPResponse {
        let body = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["role": "assistant", "content": content]]]])
        return HTTPResponse(status: 200, body: body)
    }

    private func bodyJSON(_ request: HTTPRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.body ?? Data())) as? [String: Any] ?? [:]
    }

    private func weekJSON(_ workouts: [WorkoutSpec]) -> String {
        String(decoding: try! JSONEncoder().encode(WeekPlanResponse(weekStart: "2026-11-16", summary: "Semaine de base.", workouts: workouts)), as: UTF8.self)
    }

    // MARK: LLMClient

    func testRequestShape() async throws {
        let http = FakeHTTP { _ in Self.completion("{}") }
        let client = LLMClient(http: http, provider: .groq, apiKey: "cle-test")
        let text = try await client.complete(system: "SYS", messages: [LLMMessage(role: "user", content: "Bonjour")],
                                             schemaName: "week_plan", schema: CoachSchemas.weekPlan)
        XCTAssertEqual(text, "{}")
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer cle-test")
        let body = bodyJSON(request)
        XCTAssertEqual(body["model"] as? String, "openai/gpt-oss-120b")
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.map { $0["role"] ?? "" }, ["system", "user"])
        let format = body["response_format"] as? [String: Any]
        XCTAssertEqual(format?["type"] as? String, "json_schema")
        let schema = format?["json_schema"] as? [String: Any]
        XCTAssertEqual(schema?["name"] as? String, "week_plan")
        XCTAssertEqual(schema?["strict"] as? Bool, true)
        XCTAssertNotNil(schema?["schema"] as? [String: Any], "schéma JSON valide, déplié")
    }

    func testSchemaRefusedFallsBackToJSONObjectOnce() async throws {
        let http = FakeHTTP { request in
            let format = (try? JSONSerialization.jsonObject(with: request.body ?? Data())) as? [String: Any]
            if (format?["response_format"] as? [String: Any])?["type"] as? String == "json_schema" {
                return json(400, #"{"message":"Invalid response_format"}"#)
            }
            return Self.completion("{\"ok\":true}")
        }
        let client = LLMClient(http: http, provider: .groq, apiKey: "k")
        _ = try await client.complete(system: "SYS", messages: [], schemaName: "x", schema: "{}")
        _ = try await client.complete(system: "SYS", messages: [], schemaName: "x", schema: "{}")
        XCTAssertEqual(http.requests.count, 3, "le refus du schéma est mémorisé")
        let retry = bodyJSON(http.requests[1])
        XCTAssertEqual((retry["response_format"] as? [String: Any])?["type"] as? String, "json_object")
        let system = (retry["messages"] as? [[String: String]])?.first?["content"] ?? ""
        XCTAssertTrue(system.contains("SCHÉMA JSON"), "schéma recopié dans le prompt")
    }

    func testErrorMapping() async {
        for (status, expected) in [(401, LLMError.unauthorized), (429, .rateLimited), (500, .http(500))] {
            let client = LLMClient(http: FakeHTTP { _ in json(status, "{}") }, provider: .groq, apiKey: "k")
            do {
                _ = try await client.complete(system: "", messages: [], schemaName: "x", schema: "{}")
                XCTFail("\(status) aurait dû échouer")
            } catch {
                XCTAssertEqual(error as? LLMError, expected)
            }
        }
        let empty = LLMClient(http: FakeHTTP { _ in json(200, #"{"choices":[]}"#) }, provider: .groq, apiKey: "k")
        do {
            _ = try await empty.complete(system: "", messages: [], schemaName: "x", schema: "{}")
            XCTFail("réponse vide")
        } catch {
            XCTAssertEqual(error as? LLMError, .invalidOutput)
        }
    }

    // MARK: CoachEngine

    /// Réponses servies dans l'ordre.
    private final class Queue: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [HTTPResponse]
        init(_ items: [HTTPResponse]) { self.items = items }
        func next() -> HTTPResponse { lock.lock(); defer { lock.unlock() }; return items.removeFirst() }
    }

    private func engine(_ responses: [HTTPResponse]) -> (LLMClient, FakeHTTP) {
        let queue = Queue(responses)
        let http = FakeHTTP { _ in queue.next() }
        return (LLMClient(http: http, provider: .groq, apiKey: "k"), http)
    }

    func testValidAIWeekIsKeptWithRecomputedEstimates() async {
        var week = GuardrailsTests.week()
        week[0].estimatedDistanceKm = 99   // jamais cru
        week[0].title = String(repeating: "x", count: 80)
        let (llm, http) = engine([Self.completion(weekJSON(week))])
        let result = await CoachEngine.generateWeek(llm: llm, snapshot: GuardrailsTests.snapshot(), brief: GuardrailsTests.brief(), recentPlan: "[]")
        XCTAssertEqual(result.source, "ai")
        XCTAssertNil(result.notice)
        XCTAssertEqual(result.workouts.count, 4)
        XCTAssertEqual(result.workouts[0].estimatedDistanceKm ?? 0, 5.5, accuracy: 0.05, "40 min à 7:19,5 /km")
        XCTAssertEqual(result.workouts[0].title.count, 40)
        XCTAssertEqual(http.requests.count, 1)
    }

    func testInvalidWeekIsRepairedOnce() async {
        var bad = GuardrailsTests.week()
        bad[0].date = "2026-11-16"   // G7 : jour non disponible
        let (llm, http) = engine([Self.completion(weekJSON(bad)), Self.completion(weekJSON(GuardrailsTests.week()))])
        let result = await CoachEngine.generateWeek(llm: llm, snapshot: GuardrailsTests.snapshot(), brief: GuardrailsTests.brief(), recentPlan: "[]")
        XCTAssertEqual(result.source, "ai")
        XCTAssertEqual(http.requests.count, 2)
        let messages = (bodyJSON(http.requests[1])["messages"] as? [[String: String]]) ?? []
        XCTAssertEqual(messages.map { $0["role"] ?? "" }, ["system", "user", "assistant", "user"])
        XCTAssertTrue(messages.last?["content"]?.contains("G7") ?? false, "la violation est citée")
    }

    func testFallbackAfterFailedRepairOrError() async {
        let (llm, http) = engine([Self.completion("pas du JSON"), Self.completion("toujours pas")])
        let result = await CoachEngine.generateWeek(llm: llm, snapshot: GuardrailsTests.snapshot(), brief: GuardrailsTests.brief(), recentPlan: "[]")
        XCTAssertEqual(result.source, "fallback")
        XCTAssertNotNil(result.notice)
        XCTAssertFalse(result.workouts.isEmpty)
        XCTAssertEqual(http.requests.count, 2, "une seule réparation")

        let (limited, _) = engine([json(429, "{}")])
        let quota = await CoachEngine.generateWeek(llm: limited, snapshot: GuardrailsTests.snapshot(), brief: GuardrailsTests.brief(), recentPlan: "[]")
        XCTAssertEqual(quota.source, "fallback")
        XCTAssertEqual(quota.notice, LLMError.rateLimited.userMessage)

        let none = await CoachEngine.generateWeek(llm: nil, snapshot: GuardrailsTests.snapshot(), brief: GuardrailsTests.brief(), recentPlan: "[]")
        XCTAssertEqual(none.notice, LLMError.missingKey.userMessage)
        XCTAssertEqual(Guardrails.validate(week: none.workouts, brief: GuardrailsTests.brief(), snapshot: GuardrailsTests.snapshot()), [])
    }

    // MARK: SnapshotBuilder

    private func input(runs: [RunSummary]) -> SnapshotBuilder.Input {
        let today = DayKey.date("2026-11-13")!
        return SnapshotBuilder.Input(
            today: today, birthDate: DayKey.date("2005-03-01")!, sex: nil, runningSince: DayKey.date("2026-10-20")!,
            injuryNote: "", currentPain: false, fatigueLevel: "normal", wantsStrength: true, strengthEquipment: "none",
            onboardingRun: RunSummary(date: today, distanceM: 5000, durationS: 1950), onboardingEffort: "moderate",
            thresholdOverrideSPerKm: nil, hrMaxBpm: 194, goalKind: "race", goalDistanceKm: 21.1,
            goalDate: DayKey.date("2027-05-16")!, goalTargetS: 7200, runs: runs,
            recovery: .init(sleepHAvg7d: 7.2, hrvStatus: nil, restingHr: 58), missedLast14d: 0)
    }

    func testSnapshotWithoutHistoryUsesOnboarding() {
        let snapshot = SnapshotBuilder.snapshot(input(runs: []))
        XCTAssertEqual(snapshot.pace(.easy), PaceRange(fastSPerKm: 418, slowSPerKm: 461), "5 km en 32:30, ressenti modéré")
        XCTAssertEqual(snapshot.athlete.age, 21)
        XCTAssertEqual(snapshot.athlete.level, "beginner")
        XCTAssertEqual(snapshot.goal.weeksLeft, 27)
        XCTAssertEqual(snapshot.goal.targetPaceSPerKm, 341)
        XCTAssertEqual(snapshot.goal.feasibility, .ambitious)
        XCTAssertEqual(snapshot.hrZonesBpm.first, [97, 116])
        XCTAssertEqual(snapshot.lastWeeks, [], "sans historique, pas de semaines à zéro")
        let base = SnapshotBuilder.baseline(input(runs: []), sessionsPerWeek: 3)
        XCTAssertEqual(base.v0Km, 15)
        XCTAssertEqual(base.l0Km, 5)
    }

    func testSnapshotAggregatesCompleteWeeksOnly() {
        func run(_ day: String, km: Double) -> RunSummary {
            RunSummary(date: DayKey.date(day)!, distanceM: km * 1000, durationS: km * 400, avgHR: 150)
        }
        // Semaine en cours (à partir du lundi 10) exclue des semaines complètes.
        let runs = [run("2026-10-28", km: 5), run("2026-11-02", km: 6), run("2026-11-04", km: 4), run("2026-11-11", km: 7)]
        let snapshot = SnapshotBuilder.snapshot(input(runs: runs))
        XCTAssertEqual(snapshot.lastWeeks.map(\.weekStart), ["2026-10-26", "2026-11-02"])
        XCTAssertEqual(snapshot.lastWeeks.map(\.km), [5, 10])
        XCTAssertEqual(snapshot.lastWeeks.last?.longestKm, 6)
        XCTAssertEqual(snapshot.lastRuns.first?.date, "2026-11-11")
        XCTAssertEqual(snapshot.lastRuns.first?.paceSPerKm, 400)
        let base = SnapshotBuilder.baseline(input(runs: runs), sessionsPerWeek: 3)
        XCTAssertEqual(base.v0Km, 7.5)
        XCTAssertEqual(base.l0Km, 6)
        // Le résumé ne contient que des agrégats.
        let text = Prompts.json(snapshot)
        XCTAssertFalse(text.contains("lat"), "aucune coordonnée")
    }
}
