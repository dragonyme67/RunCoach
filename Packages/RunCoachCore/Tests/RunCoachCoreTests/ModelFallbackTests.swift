import XCTest
@testable import RunCoachCore

/// Bascule d'un modèle à l'autre quand un quota est atteint, et choix du modèle selon la question.
final class ModelFallbackTests: XCTestCase {
    private static let ok = HTTPResponse(status: 200, body: try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": "{}"]]]]))

    private func model(_ request: HTTPRequest) -> String {
        ((try? JSONSerialization.jsonObject(with: request.body ?? Data())) as? [String: Any])?["model"] as? String ?? ""
    }

    func testRateLimitedModelIsSkippedAndRemembered() async throws {
        let http = FakeHTTP { request in
            let body = (try? JSONSerialization.jsonObject(with: request.body ?? Data())) as? [String: Any]
            return body?["model"] as? String == "gemini-3.8-flash"
                ? json(429, #"[{"error":{"code":429,"message":"Quota exceeded for requests per day"}}]"#)
                : Self.ok
        }
        let lines = Lines()
        let client = LLMClient(http: http, provider: .gemini, apiKey: "k", log: { lines.add($0) })
        _ = try await client.complete(system: "", messages: [], schemaName: "x", schema: "{}", tier: .hard)
        _ = try await client.complete(system: "", messages: [], schemaName: "x", schema: "{}", tier: .hard)
        XCTAssertEqual(http.requests.map(model), ["gemini-3.8-flash", "gemini-3.6-flash", "gemini-3.6-flash"],
                       "le modèle épuisé n'est plus essayé")
        XCTAssertTrue(lines.all.first?.contains("HTTP 429") ?? false)
        XCTAssertTrue(lines.all.first?.contains("Quota exceeded for requests per day") ?? false, "message de Google dans le diagnostic")
    }

    func testLightRequestsStartWithTheLightestModel() async throws {
        let http = FakeHTTP { _ in Self.ok }
        let client = LLMClient(http: http, provider: .groq, apiKey: "k")
        _ = try await client.complete(system: "", messages: [], schemaName: "x", schema: "{}", tier: .light)
        XCTAssertEqual(http.requests.map(model), ["openai/gpt-oss-20b"])
    }

    func testUnauthorizedStopsImmediately() async {
        let http = FakeHTTP { _ in json(401, "{}") }
        let client = LLMClient(http: http, provider: .gemini, apiKey: "k")
        do {
            _ = try await client.complete(system: "", messages: [], schemaName: "x", schema: "{}")
            XCTFail("clé refusée")
        } catch {
            XCTAssertEqual(error as? LLMError, .unauthorized)
        }
        XCTAssertEqual(http.requests.count, 1, "aucun autre modèle n'y changerait rien")
    }

    func testChatTier() {
        XCTAssertEqual(Prompts.chatTier("Bonjour, ça va ?"), .light)
        XCTAssertEqual(Prompts.chatTier("Merci !"), .light)
        XCTAssertEqual(Prompts.chatTier("Comment se déroule ma séance de renfo de demain ?"), .hard)
        XCTAssertEqual(Prompts.chatTier("Fais-moi un bilan"), .hard)
        XCTAssertEqual(Prompts.chatTier("J'ai mal au genou"), .hard)
        XCTAssertEqual(Prompts.chatTier(String(repeating: "blabla ", count: 30)), .hard, "message long")
    }

    func testErrorMessageExtraction() {
        XCTAssertEqual(LLMClient.errorMessage(Data(#"{"error":{"message":"Invalid model"}}"#.utf8)), "Invalid model")
        XCTAssertEqual(LLMClient.errorMessage(Data("Service Unavailable".utf8)), "Service Unavailable")
    }
}

/// Lignes du journal, écrites depuis l'acteur.
private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ line: String) { lock.lock(); items.append(line); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
