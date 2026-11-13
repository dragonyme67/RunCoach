import Foundation
@testable import RunCoachCore

/// Serveur simulé : aucune requête ne quitte la machine de test.
final class FakeHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [HTTPRequest] = []
    private let handler: @Sendable (HTTPRequest) throws -> HTTPResponse

    init(_ handler: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse) {
        self.handler = handler
    }

    var requests: [HTTPRequest] { lock.lock(); defer { lock.unlock() }; return _requests }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock(); _requests.append(request); lock.unlock()
        // Laisse d'autres tâches s'intercaler, comme un vrai aller-retour réseau.
        try await Task.sleep(nanoseconds: 20_000_000)
        return try handler(request)
    }
}

final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    init(_ values: [String: String] = [:]) { self.values = values }

    func read(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func write(_ key: String, _ value: String?) { lock.lock(); values[key] = value; lock.unlock() }
}

/// JWT non signé portant `exp` et `client_id`.
func makeJWT(exp: Date, clientId: String = "GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2", tag: String = "a") -> String {
    let payload = #"{"exp":\#(Int(exp.timeIntervalSince1970)),"client_id":"\#(clientId)","tag":"\#(tag)"}"#
    let b64 = Data(payload.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJub25lIn0.\(b64).sig"
}

func json(_ status: Int, _ text: String) -> HTTPResponse {
    HTTPResponse(status: status, body: Data(text.utf8))
}

func formFields(_ request: HTTPRequest) -> [String: String] {
    let text = String(decoding: request.body ?? Data(), as: UTF8.self)
    var fields: [String: String] = [:]
    for pair in text.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        fields[parts[0]] = parts.count > 1 ? parts[1].removingPercentEncoding : ""
    }
    return fields
}
