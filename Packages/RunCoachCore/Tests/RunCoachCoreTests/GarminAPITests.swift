import XCTest
@testable import RunCoachCore

final class GarminAPITests: XCTestCase {
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var waits: [TimeInterval] = []
    }

    private func makeAPI(_ handler: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse,
                         store: MemoryTokenStore? = nil, clock: Clock = Clock()) -> (GarminAPI, FakeHTTP) {
        let http = FakeHTTP(handler)
        let token = makeJWT(exp: clock.now.addingTimeInterval(90_000))
        let tokens = store ?? MemoryTokenStore([GarminAuth.Key.token: token, GarminAuth.Key.refresh: "R", GarminAuth.Key.clientId: "C"])
        let auth = GarminAuth(http: http, store: tokens, now: { clock.now })
        let api = GarminAPI(auth: auth, http: http, interval: 1, now: { clock.now },
                            pause: { clock.waits.append($0); clock.now.addTimeInterval($0) })
        return (api, http)
    }

    func testRequestsCarryIdentityAndAreSpaced() async throws {
        let clock = Clock()
        let (api, http) = makeAPI({ _ in json(200, "[]") }, clock: clock)
        _ = try await api.activities(start: 0, limit: 100)
        _ = try await api.activities(start: 100, limit: 100)

        let request = http.requests[0]
        XCTAssertEqual(request.url.host, "connectapi.garmin.com")
        XCTAssertEqual(request.url.path, "/activitylist-service/activities/search/activities")
        XCTAssertEqual(request.url.query, "limit=100&start=0")
        XCTAssertTrue(request.headers["Authorization"]?.hasPrefix("Bearer ") == true)
        XCTAssertEqual(request.headers["User-Agent"], "GCM-Android-5.23")
        XCTAssertEqual(clock.waits, [1], "1 s entre deux requêtes")
        let count = await api.requestCount
        XCTAssertEqual(count, 2)
    }

    func testUnauthorizedRefreshesOnceThenRetries() async throws {
        let clock = Clock()
        let fresh = makeJWT(exp: clock.now.addingTimeInterval(90_000), tag: "fresh")
        let (api, http) = makeAPI({ request in
            if request.url.host == "diauth.garmin.com" {
                return json(200, #"{"access_token":"\#(fresh)","refresh_token":"R2"}"#)
            }
            return request.headers["Authorization"] == "Bearer \(fresh)" ? json(200, #"{"displayName":"x"}"#) : json(401, "")
        }, clock: clock)
        let profile = try await api.socialProfile()
        XCTAssertEqual(profile.displayName, "x")
        XCTAssertEqual(http.requests.map { $0.url.host ?? "" },
                       ["connectapi.garmin.com", "diauth.garmin.com", "connectapi.garmin.com"])
    }

    func testStatusCodesMapToErrors() async {
        for (status, expected) in [(429, GarminError.rateLimited), (427, .rateLimited), (403, .blocked), (404, .http(404))] {
            let (api, _) = makeAPI({ _ in json(status, "") })
            do {
                _ = try await api.socialProfile()
                XCTFail("erreur attendue pour \(status)")
            } catch {
                XCTAssertEqual(error as? GarminError, expected)
            }
        }
    }

    func testNetworkFailureAndBadJSON() async {
        struct Offline: Error {}
        let (offline, _) = makeAPI({ _ in throw Offline() })
        do { _ = try await offline.socialProfile(); XCTFail() } catch { XCTAssertEqual(error as? GarminError, .network) }
        let (garbled, _) = makeAPI({ _ in json(200, "<html>") })
        do { _ = try await garbled.socialProfile(); XCTFail() } catch { XCTAssertEqual(error as? GarminError, .decoding) }
    }

    func testNoTokenMeansNeedsLogin() async {
        let (api, http) = makeAPI({ _ in json(200, "{}") }, store: MemoryTokenStore())
        do { _ = try await api.socialProfile(); XCTFail() } catch { XCTAssertEqual(error as? GarminError, .needsLogin) }
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testWorkoutCreateScheduleListDelete() async throws {
        let (api, http) = makeAPI({ request in
            switch (request.method, request.url.path) {
            case ("POST", "/workout-service/workout"): return json(200, #"{"workoutId":123,"workoutName":"RC · x"}"#)
            case ("POST", "/workout-service/schedule/123"): return json(200, #"{"workoutScheduleId":456}"#)
            case ("GET", "/workout-service/workouts"): return json(200, #"[{"workoutId":123,"workoutName":"RC · x"}]"#)
            case ("DELETE", "/workout-service/workout/123"): return HTTPResponse(status: 204)
            default: return json(404, "")
            }
        })
        let id = try await api.createWorkout(Data(#"{"workoutName":"RC · x"}"#.utf8))
        XCTAssertEqual(id, 123)
        let scheduleId = try await api.schedule(workoutId: id, day: "2026-11-18")
        XCTAssertEqual(scheduleId, 456)
        let list = try await api.workouts()
        XCTAssertEqual(list, [WorkoutRefDTO(workoutId: 123, workoutName: "RC · x")])
        try await api.deleteWorkout(id)

        XCTAssertEqual(http.requests[0].headers["Content-Type"], "application/json")
        XCTAssertEqual(String(decoding: http.requests[1].body ?? Data(), as: UTF8.self), #"{"date":"2026-11-18"}"#)
        XCTAssertEqual(http.requests[2].url.query, "limit=100&myWorkoutsOnly=true&start=0")
        XCTAssertNil(http.requests[3].body)
    }
}
