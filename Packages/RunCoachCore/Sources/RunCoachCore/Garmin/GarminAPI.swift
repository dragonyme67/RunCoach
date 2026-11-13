import Foundation

/// Appels à `connectapi.garmin.com` (ARCHITECTURE.md §5.1.5, §5.2).
/// Les requêtes partent une par une, espacées d'au moins `interval` secondes (règles anti-blocage §5.1.6).
public actor GarminAPI {
    private let auth: GarminAuth
    private let http: HTTPClient
    private let interval: TimeInterval
    private let now: @Sendable () -> Date
    private let pause: @Sendable (TimeInterval) async throws -> Void
    private var nextSlot = Date.distantPast
    public private(set) var requestCount = 0

    public init(auth: GarminAuth, http: HTTPClient, interval: TimeInterval = 1,
                now: @escaping @Sendable () -> Date = { Date() },
                pause: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1e9)) }) {
        self.auth = auth
        self.http = http
        self.interval = interval
        self.now = now
        self.pause = pause
    }

    public func socialProfile() async throws -> SocialProfileDTO {
        try await get("/userprofile-service/socialProfile")
    }

    /// Page de la liste, de la plus récente à la plus ancienne.
    public func activities(start: Int, limit: Int) async throws -> [ActivityDTO] {
        try await get("/activitylist-service/activities/search/activities",
                      query: ["start": "\(start)", "limit": "\(limit)"])
    }

    // shortcut: le polyligne (doublon des colonnes) est aussi téléchargé ; maxPolylineSize=0 non testé, à essayer si le volume 4G gêne.
    public func details(activityId: Int64) async throws -> ActivityDetailsDTO {
        try await get("/activity-service/activity/\(activityId)/details",
                      query: ["maxChartSize": "2000", "maxPolylineSize": "4000"])
    }

    public func sleep(day: String) async throws -> SleepDTO {
        try await get("/sleep-service/sleep/dailySleepData", query: ["date": day, "nonSleepBufferMinutes": "60"])
    }

    public func trainingStatus(day: String) async throws -> TrainingStatusDTO {
        try await get("/metrics-service/metrics/trainingstatus/aggregated/\(day)")
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var components = URLComponents(string: GarminIdentity.apiBase.absoluteString + path)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let url = components.url!

        var token = try await auth.validToken()
        var response = try await send(url, token: token)
        if response.status == 401 {
            token = try await auth.refresh(rejected: token)
            response = try await send(url, token: token)
        }
        switch response.status {
        case 200..<300:
            do { return try JSONDecoder().decode(T.self, from: response.body) } catch { throw GarminError.decoding }
        case 403: throw GarminError.blocked
        case 427, 429: throw GarminError.rateLimited
        default: throw GarminError.http(response.status)
        }
    }

    private func send(_ url: URL, token: String) async throws -> HTTPResponse {
        // Créneau réservé avant d'attendre : même deux appels simultanés restent espacés.
        let slot = max(now(), nextSlot)
        nextSlot = slot.addingTimeInterval(interval)
        let wait = slot.timeIntervalSince(now())
        if wait > 0 { try await pause(wait) }
        requestCount += 1

        var headers = GarminIdentity.headers
        headers["Authorization"] = "Bearer \(token)"
        headers["Accept"] = "application/json"
        do {
            return try await http.send(HTTPRequest(method: "GET", url: url, headers: headers))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GarminError.network
        }
    }
}
