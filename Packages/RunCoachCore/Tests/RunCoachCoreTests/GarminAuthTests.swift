import XCTest
@testable import RunCoachCore

final class GarminAuthTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testExchangeTriesNextClientIdAndStoresTokens() async throws {
        let access = makeJWT(exp: now.addingTimeInterval(90_000), clientId: "FROM_JWT")
        let http = FakeHTTP { request in
            let fields = formFields(request)
            XCTAssertEqual(fields["service_ticket"], "ST-123-abc")
            XCTAssertEqual(fields["service_url"], GarminIdentity.serviceURL)
            XCTAssertEqual(request.headers["Authorization"],
                           "Basic " + Data("\(fields["client_id"]!):".utf8).base64EncodedString())
            if fields["client_id"] == GarminIdentity.diClientIds[0] { return json(400, "{}") }
            return json(200, #"{"access_token":"\#(access)","refresh_token":"R1","expires_in":90000}"#)
        }
        let store = MemoryTokenStore()
        let auth = GarminAuth(http: http, store: store, now: { self.now })

        try await auth.exchange(ticket: "ST-123-abc")

        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(store.read(GarminAuth.Key.token), access)
        XCTAssertEqual(store.read(GarminAuth.Key.refresh), "R1")
        XCTAssertEqual(store.read(GarminAuth.Key.clientId), "FROM_JWT")
        XCTAssertTrue(auth.hasSession)
    }

    func testExchangeStopsOnRateLimit() async {
        let http = FakeHTTP { _ in json(429, "") }
        let auth = GarminAuth(http: http, store: MemoryTokenStore())
        do {
            try await auth.exchange(ticket: "ST-1")
            XCTFail("429 attendu")
        } catch {
            XCTAssertEqual(error as? GarminError, .rateLimited)
        }
        XCTAssertEqual(http.requests.count, 1, "aucun autre client_id après un 429")
    }

    func testValidTokenDoesNotRefreshWhenFarFromExpiry() async throws {
        let token = makeJWT(exp: now.addingTimeInterval(3600))
        let http = FakeHTTP { _ in json(500, "") }
        let auth = GarminAuth(http: http, store: MemoryTokenStore([GarminAuth.Key.token: token]), now: { self.now })
        let valid = try await auth.validToken()
        XCTAssertEqual(valid, token)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testConcurrentRefreshesMakeOneCallAndPersistRotatedRefreshToken() async throws {
        let old = makeJWT(exp: now.addingTimeInterval(60), tag: "old")
        let fresh = makeJWT(exp: now.addingTimeInterval(90_000), tag: "new")
        let http = FakeHTTP { request in
            XCTAssertEqual(formFields(request)["refresh_token"], "R1")
            return json(200, #"{"access_token":"\#(fresh)","refresh_token":"R2"}"#)
        }
        let store = MemoryTokenStore([GarminAuth.Key.token: old, GarminAuth.Key.refresh: "R1",
                                      GarminAuth.Key.clientId: "CID"])
        let auth = GarminAuth(http: http, store: store, now: { self.now })

        async let a = auth.validToken()
        async let b = auth.validToken()
        async let c = auth.refresh(rejected: old)
        let tokens = try await [a, b, c]

        XCTAssertEqual(tokens, [fresh, fresh, fresh])
        XCTAssertEqual(http.requests.count, 1, "un seul rafraîchissement")
        XCTAssertEqual(store.read(GarminAuth.Key.refresh), "R2")
    }

    func testRefreshKeepsOldRefreshTokenWhenNoneReturned() async throws {
        let fresh = makeJWT(exp: now.addingTimeInterval(90_000))
        let store = MemoryTokenStore([GarminAuth.Key.token: "x", GarminAuth.Key.refresh: "R1", GarminAuth.Key.clientId: "CID"])
        let auth = GarminAuth(http: FakeHTTP { _ in json(200, #"{"access_token":"\#(fresh)"}"#) }, store: store)
        _ = try await auth.refresh(rejected: "x")
        XCTAssertEqual(store.read(GarminAuth.Key.refresh), "R1")
    }

    func testRefusedRefreshClearsSession() async {
        let store = MemoryTokenStore([GarminAuth.Key.token: "x", GarminAuth.Key.refresh: "R1", GarminAuth.Key.clientId: "CID"])
        let auth = GarminAuth(http: FakeHTTP { _ in json(401, "") }, store: store)
        do {
            _ = try await auth.refresh(rejected: "x")
            XCTFail("needsLogin attendu")
        } catch {
            XCTAssertEqual(error as? GarminError, .needsLogin)
        }
        XCTAssertNil(store.read(GarminAuth.Key.refresh))
        XCTAssertFalse(auth.hasSession)
    }

    func testBlockedRefreshKeepsSession() async {
        let store = MemoryTokenStore([GarminAuth.Key.token: "x", GarminAuth.Key.refresh: "R1", GarminAuth.Key.clientId: "CID"])
        let auth = GarminAuth(http: FakeHTTP { _ in json(403, "") }, store: store)
        do {
            _ = try await auth.refresh(rejected: "x")
            XCTFail("blocked attendu")
        } catch {
            XCTAssertEqual(error as? GarminError, .blocked)
        }
        XCTAssertEqual(store.read(GarminAuth.Key.refresh), "R1")
    }

    func testFormBodyEncodesUrlValues() {
        let body = String(decoding: GarminAuth.formBody([("service_url", "https://a.b/c d")]), as: UTF8.self)
        XCTAssertEqual(body, "service_url=https%3A%2F%2Fa.b%2Fc%20d")
    }

    func testTicketExtraction() {
        XCTAssertEqual(GarminIdentity.ticket(in: "https://mobile.integration.garmin.com/gcm/ios?ticket=ST-0123-AbC-cas&x=1"), "ST-0123-AbC-cas")
        XCTAssertEqual(GarminIdentity.ticket(in: #"{"serviceTicketId": "ST-9-z"}"#), "ST-9-z")
        XCTAssertEqual(GarminIdentity.ticket(in: "ST-42-q"), "ST-42-q")
        XCTAssertNil(GarminIdentity.ticket(in: "<p>TEST-1 FIRST-2</p>"))
    }
}
