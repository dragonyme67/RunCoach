import Foundation

public enum LLMError: Error, Equatable, Sendable {
    case missingKey, unauthorized, rateLimited, invalidOutput, network
    case http(Int)

    /// Message affiché à l'utilisateur (ARCHITECTURE.md §5.5).
    public var userMessage: String {
        switch self {
        case .missingKey: return "Ajoute une clé IA gratuite dans Réglages."
        case .unauthorized: return "Clé IA refusée. Vérifie-la dans Réglages."
        case .rateLimited: return "Quota IA atteint sur tous les modèles. Réessaie plus tard."
        case .invalidOutput: return "Réponse de l'IA inutilisable."
        case .network: return "Pas de réponse du service d'IA."
        case .http(let code): return "Le service d'IA a répondu par une erreur (\(code)). Détail dans Réglages → Coach IA → Diagnostic."
        }
    }
}

/// Difficulté d'une demande : `hard` commence par le meilleur modèle, `light` par le plus léger (quotas plus larges).
public enum LLMTier: Sendable {
    case hard, light
}

/// Fournisseur au format « OpenAI chat completions » (ARCHITECTURE.md §5.4), avec ses modèles du plus capable au plus léger.
/// Quand un modèle atteint sa limite, la demande passe au suivant (demande de l'utilisateur du 2026-11-13).
public struct LLMProvider: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: URL
    /// Du plus capable au plus léger. Identifiants relevés dans la documentation officielle, jamais de mémoire.
    public var models: [String]

    public init(id: String, name: String, baseURL: URL, models: [String]) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.models = models
    }

    /// Ordre d'essai : le meilleur d'abord pour une demande difficile, le plus léger d'abord sinon.
    public func models(for tier: LLMTier) -> [String] {
        tier == .hard ? models : models.reversed()
    }

    /// Groq (docs lues le 2026-11-13) : modèles de production, `json_schema` strict pris en charge par les deux.
    public static let groq = LLMProvider(id: "groq", name: "Groq", baseURL: URL(string: "https://api.groq.com/openai/v1")!,
                                         models: ["openai/gpt-oss-120b", "openai/gpt-oss-20b"])
    /// Gemini (docs lues le 2026-11-13) : modèles marqués « Stable » ; point d'accès compatible OpenAI en bêta,
    /// `json_schema` non documenté dessus (repli `json_object` automatique). Quotas gratuits par modèle et par jour.
    public static let gemini = LLMProvider(id: "gemini", name: "Gemini",
                                           baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!,
                                           models: ["gemini-3.8-flash", "gemini-3.6-flash", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite"])
    public static let presets = [groq, gemini]
}

public struct LLMMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// Appels au fournisseur d'IA. Réponse attendue : un objet JSON conforme au schéma donné.
/// Garder une instance par fournisseur : elle retient les modèles épuisés et ceux qui refusent `json_schema`.
public actor LLMClient {
    private let http: HTTPClient
    private let provider: LLMProvider
    private let apiKey: String
    /// Journal de diagnostic : modèle, mode, code HTTP, durée, message d'erreur du fournisseur. Jamais le contenu envoyé.
    private let log: (@Sendable (String) -> Void)?
    /// Modèles qui ont refusé `json_schema` : on reste en `json_object` avec eux.
    private var jsonObjectOnly: Set<String> = []
    /// Modèles à éviter jusqu'à cette date (quota atteint, modèle indisponible).
    private var unavailableUntil: [String: Date] = [:]

    public init(http: HTTPClient, provider: LLMProvider, apiKey: String, log: (@Sendable (String) -> Void)? = nil) {
        self.http = http
        self.provider = provider
        self.apiKey = apiKey
        self.log = log
    }

    /// Contenu de `choices[0].message.content`. `schema` est le texte JSON du schéma (`CoachSchemas`).
    /// Quota atteint (429), modèle introuvable (404), panne (5xx), pas de réponse ou réponse vide : modèle suivant.
    /// Clé refusée ou autre erreur de requête : arrêt, aucun autre modèle n'y changerait rien.
    /// `deadline` : passé cette heure, plus aucun modèle n'est essayé (un modèle saturé peut répondre en plus d'une minute).
    public func complete(system: String, messages: [LLMMessage], schemaName: String, schema: String,
                         tier: LLMTier = .hard, models: [String]? = nil, deadline: Date? = nil) async throws -> String {
        let candidates = models ?? provider.models(for: tier)
        let now = Date()
        let available = candidates.filter { (unavailableUntil[$0] ?? .distantPast) <= now }
        var lastError = LLMError.network
        var sawRateLimit = false
        // Tous mis de côté : on réessaie quand même, la limite a pu se réinitialiser.
        for model in available.isEmpty ? candidates : available {
            if let deadline, Date() > deadline { break }
            log?("→ \(model)")
            do {
                return try await attempt(model: model, system: system, messages: messages, schemaName: schemaName, schema: schema)
            } catch let error as LLMError {
                switch error {
                case .rateLimited:
                    sawRateLimit = true
                    unavailableUntil[model] = now.addingTimeInterval(3600)
                case .http(let code) where code == 404 || code >= 500:
                    unavailableUntil[model] = now.addingTimeInterval(code == 404 ? 86_400 : 300)
                case .network, .invalidOutput:
                    break
                default:
                    throw error
                }
                lastError = error
            }
        }
        throw sawRateLimit ? LLMError.rateLimited : lastError
    }

    private func attempt(model: String, system: String, messages: [LLMMessage], schemaName: String, schema: String) async throws -> String {
        if !jsonObjectOnly.contains(model) {
            let response = try await send(model: model, system: system, messages: messages, format: .schema(name: schemaName, schema: schema))
            // Schéma refusé : un nouvel essai en `json_object`, schéma recopié dans le prompt (§5.4).
            // Tout 400 compte : le texte de l'erreur varie selon le fournisseur.
            if response.status == 400 {
                jsonObjectOnly.insert(model)
            } else {
                return try content(response)
            }
        }
        let withSchema = system + "\n\nSCHÉMA JSON À RESPECTER :\n" + schema
        return try content(try await send(model: model, system: withSchema, messages: messages, format: .jsonObject))
    }

    private enum Format {
        case schema(name: String, schema: String)
        case jsonObject
    }

    private func send(model: String, system: String, messages: [LLMMessage], format: Format) async throws -> HTTPResponse {
        let responseFormat: [String: Any]
        let mode: String
        switch format {
        case let .schema(name, schema):
            let parsed = try JSONSerialization.jsonObject(with: Data(schema.utf8))
            responseFormat = ["type": "json_schema", "json_schema": ["name": name, "strict": true, "schema": parsed]]
            mode = "json_schema"
        case .jsonObject:
            responseFormat = ["type": "json_object"]
            mode = "json_object"
        }
        let all = [LLMMessage(role: "system", content: system)] + messages
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.4,
            "messages": all.map { ["role": $0.role, "content": $0.content] },
            "response_format": responseFormat,
        ]
        let request = HTTPRequest(
            method: "POST", url: provider.baseURL.appendingPathComponent("chat/completions"),
            headers: ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: body))
        let start = Date()
        do {
            let response = try await http.send(request)
            let seconds = String(format: "%.1f", Date().timeIntervalSince(start))
            let detail = response.status < 300 ? "" : " · " + Self.errorMessage(response.body)
            log?("\(model) · \(mode) · HTTP \(response.status) · \(seconds) s\(detail)")
            return response
        } catch {
            let seconds = String(format: "%.1f", Date().timeIntervalSince(start))
            log?("\(model) · \(mode) · pas de réponse après \(seconds) s (\(error.localizedDescription))")
            throw LLMError.network
        }
    }

    /// Message d'erreur du fournisseur (`error.message`, dans un objet ou un tableau), sinon le début du corps.
    static func errorMessage(_ body: Data) -> String {
        let json = try? JSONSerialization.jsonObject(with: body)
        let object = (json as? [String: Any]) ?? (json as? [[String: Any]])?.first
        if let message = (object?["error"] as? [String: Any])?["message"] as? String { return String(message.prefix(300)) }
        return String(String(decoding: body, as: UTF8.self).prefix(300))
    }

    private func content(_ response: HTTPResponse) throws -> String {
        switch response.status {
        case 200..<300: break
        case 401, 403: throw LLMError.unauthorized
        case 429: throw LLMError.rateLimited
        default: throw LLMError.http(response.status)
        }
        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let completion = try? JSONDecoder().decode(Completion.self, from: response.body),
              let text = completion.choices.first?.message.content, !text.isEmpty else {
            throw LLMError.invalidOutput
        }
        return text
    }
}
