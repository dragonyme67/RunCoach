import Foundation
import RunCoachCore

/// Session éphémère : aucun cookie ni cache gardé entre deux appels à Garmin.
struct URLSessionHTTPClient: HTTPClient {
    /// 30 s par défaut (Garmin) ; 60 s pour l'IA, qui peut mettre longtemps à rédiger une semaine (§5.4).
    var timeoutS: TimeInterval = 30

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = timeoutS
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await Self.session.data(for: urlRequest)
        return HTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }
}
