import XCTest
@testable import RunCoachCore

final class AnalysisChatTests: XCTestCase {
    private let today = DayKey.date("2026-11-13")!

    /// Sortie de 50 min à 3 m/s (5:33 /km) ; FC 140 puis 150 à partir de la mi-parcours (hors 10 premières minutes).
    private func driftingTrack() -> Track {
        let t = stride(from: 0.0, through: 3000, by: 10).map { $0 }
        return Track(t: t, lat: t.map { _ in 0 }, lon: t.map { _ in 0 }, dist: t.map { $0 * 3 },
                     hr: t.map { $0 < 1800 ? 140 : 150 }, speed: t.map { _ in 3 })
    }

    func testCardiacDrift() {
        XCTAssertEqual(FitnessAnalyzer.driftPct(driftingTrack()) ?? 0, (1 - 140.0 / 150) * 100, accuracy: 1e-9)
        var short = driftingTrack()
        short.t = short.t.map { $0 / 2 }
        XCTAssertNil(FitnessAnalyzer.driftPct(short), "moins de 40 min")
    }

    func testAnalysisOverSixWeeks() throws {
        let recent = AnalyzedRun(
            summary: RunSummary(date: DayKey.addDays(-2, to: today), distanceM: 9000, durationS: 3000,
                                hrZoneSeconds: [600, 1800, 300, 300, 0], avgHR: 145),
            track: driftingTrack(), avgCadenceSpm: 170, elevationGainM: 50)
        let before = AnalyzedRun(
            summary: RunSummary(date: DayKey.addDays(-30, to: today), distanceM: 5000, durationS: 2000, avgHR: 150),
            avgCadenceSpm: 160, elevationGainM: 30)
        let old = AnalyzedRun(summary: RunSummary(date: DayKey.addDays(-60, to: today), distanceM: 20000, durationS: 8000))
        let a = try XCTUnwrap(FitnessAnalyzer.analyze([recent, before, old], today: today,
                                                      easy: PaceRange(fastSPerKm: 418, slowSPerKm: 461),
                                                      tempo: PaceRange(fastSPerKm: 355, slowSPerKm: 372)))
        XCTAssertEqual(a.runs, 2, "la sortie d'il y a 60 jours est hors fenêtre")
        XCTAssertEqual(a.weeks, 5)
        XCTAssertEqual(a.runsPerWeek, 0.4)
        XCTAssertEqual(a.intensity, .init(easyPct: 80, moderatePct: 10, hardPct: 10))
        XCTAssertEqual(a.greyZoneRuns, 1, "5 km à 6:40 /km : plus vite que le footing, moins vite que le tempo")
        XCTAssertEqual(a.efficiencyRecent, 1.24)
        XCTAssertEqual(a.efficiencyBefore, 1.0)
        XCTAssertEqual(a.efficiencyChangePct, 24.1)
        XCTAssertEqual(a.cardiacDriftPct, 6.7)
        XCTAssertEqual(a.driftRuns, 1)
        XCTAssertEqual(a.splitRuns, 1)
        XCTAssertEqual(a.positiveSplitRuns, 0)
        XCTAssertEqual(a.kmPaceVariationPct, 0)
        XCTAssertEqual(a.fastestKmSPerKm, 333)
        XCTAssertEqual(a.cadenceSpm, 165)
        XCTAssertEqual(a.elevationGainMPerWeek, 16)
        XCTAssertEqual(a.longestRecentKm, 9)
        XCTAssertEqual(a.longestBeforeKm, 5)
        XCTAssertNil(FitnessAnalyzer.analyze([old], today: today, easy: nil, tempo: nil))
    }

    func testPresetsAddresses() {
        XCTAssertEqual(LLMProvider.groq.baseURL.appendingPathComponent("chat/completions").absoluteString,
                       "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(LLMProvider.gemini.baseURL.appendingPathComponent("chat/completions").absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
    }

    // MARK: Chat

    private func chat(_ content: String) async throws -> (ChatResponse, FakeHTTP) {
        let body = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        let http = FakeHTTP { _ in HTTPResponse(status: 200, body: body) }
        let llm = LLMClient(http: http, provider: .groq, apiKey: "k")
        let outcome = try await CoachEngine.chat(llm: llm, todayLabel: "vendredi 13 novembre 2026", todayKey: "2026-11-13",
                                                 snapshot: GuardrailsTests.snapshot(), upcoming: "[]", planned: [], briefs: [],
                                                 history: [LLMMessage(role: "user", content: "Salut")],
                                                 message: "Comment se passe mon renfo demain ?")
        return (outcome.response, http)
    }

    func testChatSanitizesAndForcesPainOnSafety() async throws {
        let (response, http) = try await chat(#"{"reply":"Arrête-toi et repose-toi.","profile_patch":{"current_pain":null,"fatigue_level":"extreme","injury_note":null},"safety":"pain"}"#)
        XCTAssertEqual(response.reply, "Arrête-toi et repose-toi.")
        XCTAssertNil(response.profilePatch.fatigueLevel, "valeur hors liste ignorée")
        XCTAssertEqual(response.profilePatch.currentPain, true, "douleur déclarée : mode prudent")
        let body = (try JSONSerialization.jsonObject(with: http.requests[0].body!)) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        XCTAssertTrue(messages[0]["content"]!.contains("PRIORITÉ"))
        XCTAssertTrue(messages[1]["content"]!.contains("ATHLÈTE : Salut"))
        XCTAssertTrue(messages[1]["content"]!.contains("vendredi 13 novembre 2026"))
        XCTAssertEqual(((body["response_format"] as! [String: Any])["json_schema"] as! [String: Any])["name"] as? String, "chat_response")
    }

    func testChatRejectsUnusableReply() async {
        do {
            _ = try await chat("pas du JSON")
            XCTFail("réponse inutilisable")
        } catch {
            XCTAssertEqual(error as? LLMError, .invalidOutput)
        }
    }
}
