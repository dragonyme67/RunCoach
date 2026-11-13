import Foundation

/// Jetons « DI OAuth2 » de Garmin : échange du ticket de connexion, rafraîchissement (ARCHITECTURE.md §5.1.3, §5.1.4).
/// `actor` : un seul rafraîchissement à la fois. Deux rafraîchissements parallèles avec le même jeton
/// invalideraient la session, car Garmin fait tourner le jeton de rafraîchissement à chaque appel.
public actor GarminAuth {
    public enum Key {
        public static let token = "di_token"
        public static let refresh = "di_refresh_token"
        public static let clientId = "di_client_id"
    }

    private let http: HTTPClient
    private let store: TokenStore
    private let now: @Sendable () -> Date
    private var refreshing: Task<String, Error>?

    public init(http: HTTPClient, store: TokenStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http
        self.store = store
        self.now = now
    }

    public nonisolated var hasSession: Bool { store.read(Key.refresh) != nil }

    /// Échange le ticket `ST-…` capté à la connexion. Le ticket est à usage unique : appelé une seule fois.
    public func exchange(ticket: String) async throws {
        for clientId in GarminIdentity.diClientIds {
            let response = try await post(clientId: clientId, accept: "application/json,text/html;q=0.9,*/*;q=0.8", form: [
                ("client_id", clientId),
                ("service_ticket", ticket),
                ("grant_type", GarminIdentity.ticketGrantType),
                ("service_url", GarminIdentity.serviceURL),
            ])
            if response.status == 427 || response.status == 429 { throw GarminError.rateLimited }
            guard response.status == 200,
                  let tokens = try? JSONDecoder().decode(TokenResponseDTO.self, from: response.body),
                  let access = tokens.accessToken else { continue }
            save(access: access, refresh: tokens.refreshToken, clientId: clientId)
            return
        }
        throw GarminError.needsLogin
    }

    /// Jeton utilisable, rafraîchi d'abord s'il expire dans moins de 15 min.
    public func validToken() async throws -> String {
        guard let token = store.read(Key.token) else { throw GarminError.needsLogin }
        // Sans date d'expiration lisible, on attend le refus (401) pour rafraîchir.
        guard let exp = JWT.expiry(token), now() >= exp.addingTimeInterval(-15 * 60) else { return token }
        return try await refresh(rejected: token)
    }

    /// Rafraîchit après un refus de `rejected`. Si un autre appel l'a déjà remplacé, renvoie simplement le nouveau.
    public func refresh(rejected: String) async throws -> String {
        if let current = store.read(Key.token), current != rejected { return current }
        if let running = refreshing { return try await running.value }
        let task = Task { try await self.performRefresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    public func logout() {
        for key in [Key.token, Key.refresh, Key.clientId] { store.write(key, nil) }
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = store.read(Key.refresh), let clientId = store.read(Key.clientId) else {
            logout()
            throw GarminError.needsLogin
        }
        let response = try await post(clientId: clientId, accept: "application/json", form: [
            ("grant_type", "refresh_token"),
            ("client_id", clientId),
            ("refresh_token", refreshToken),
        ])
        switch response.status {
        case 200:
            guard let tokens = try? JSONDecoder().decode(TokenResponseDTO.self, from: response.body),
                  let access = tokens.accessToken else { throw GarminError.decoding }
            save(access: access, refresh: tokens.refreshToken ?? refreshToken, clientId: clientId)
            return access
        case 400, 401:
            logout()
            throw GarminError.needsLogin
        case 403: throw GarminError.blocked
        case 427, 429: throw GarminError.rateLimited
        default: throw GarminError.http(response.status)
        }
    }

    /// Le jeton de rafraîchissement est écrit avant le jeton d'accès : le perdre oblige à se reconnecter.
    private func save(access: String, refresh: String?, clientId: String) {
        if let refresh { store.write(Key.refresh, refresh) }
        store.write(Key.clientId, JWT.claims(access)?["client_id"] as? String ?? clientId)
        store.write(Key.token, access)
    }

    private func post(clientId: String, accept: String, form: [(String, String)]) async throws -> HTTPResponse {
        var headers = GarminIdentity.headers
        headers["Authorization"] = "Basic " + Data("\(clientId):".utf8).base64EncodedString()
        headers["Accept"] = accept
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        headers["Cache-Control"] = "no-cache"
        let request = HTTPRequest(method: "POST", url: GarminIdentity.tokenURL, headers: headers, body: Self.formBody(form))
        do {
            return try await http.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GarminError.network
        }
    }

    static func formBody(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = pairs.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }
}

/// Lecture (sans vérification de signature) des revendications d'un JWT : seules `exp` et `client_id` servent.
enum JWT {
    static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func expiry(_ token: String) -> Date? {
        // Linux et iOS ne rendent pas les nombres JSON sous le même type.
        switch claims(token)?["exp"] {
        case let value as Double: return Date(timeIntervalSince1970: value)
        case let value as Int: return Date(timeIntervalSince1970: Double(value))
        case let value as NSNumber: return Date(timeIntervalSince1970: value.doubleValue)
        default: return nil
        }
    }
}
