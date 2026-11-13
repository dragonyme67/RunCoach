import Foundation

public enum LLMError: Error, Equatable, Sendable {
    case missingKey, unauthorized, rateLimited, invalidOutput, network
    case http(Int)

    /// Message affiché à l'utilisateur (ARCHITECTURE.md §5.5).
    public var userMessage: String {
        switch self {
        case .missingKey: return "Ajoute une clé IA gratuite dans Réglages."
        case .unauthorized: return "Clé IA refusée. Vérifie-la dans Réglages."
        case .rateLimited: return "Quota IA atteint. Plan généré sans IA en attendant."
        case .invalidOutput: return "Réponse de l'IA inutilisable."
        case .network: return "Pas de connexion au service d'IA."
        case .http(let code): return "Le service d'IA a répondu par une erreur (\(code))."
        }
    }
}

/// Fournisseur au format « OpenAI chat completions » (ARCHITECTURE.md §5.4). Modèle modifiable dans Réglages.
public struct LLMProvider: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: URL
    public var model: String

    public init(id: String, name: String, baseURL: URL, model: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
    }

    /// Choix de l'utilisateur (2026-11-13) : Groq et Gemini, gratuits, au choix dans Réglages. Mistral écarté : clé API payante.
    /// Groq (docs lues le 2026-11-13) : `json_schema` strict pris en charge par `openai/gpt-oss-120b`.
    public static let groq = LLMProvider(id: "groq", name: "Groq", baseURL: URL(string: "https://api.groq.com/openai/v1")!,
                                         model: "openai/gpt-oss-120b")
    /// Gemini (docs lues le 2026-11-13) : point d'accès compatible OpenAI, en bêta ; `json_schema` non documenté sur ce point
    /// d'accès (repli `json_object` automatique). `gemini-flash-latest` : Google prévient 2 semaines avant de changer le modèle.
    public static let gemini = LLMProvider(id: "gemini", name: "Gemini",
                                           baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!,
                                           model: "gemini-flash-latest")
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
public actor LLMClient {
    private let http: HTTPClient
    private let provider: LLMProvider
    private let apiKey: String
    /// Le fournisseur a refusé `json_schema` : on reste en `json_object` pour la suite.
    private var jsonObjectOnly = false

    public init(http: HTTPClient, provider: LLMProvider, apiKey: String) {
        self.http = http
        self.provider = provider
        self.apiKey = apiKey
    }

    /// Contenu de `choices[0].message.content`. `schema` est le texte JSON du schéma (`CoachSchemas`).
    public func complete(system: String, messages: [LLMMessage], schemaName: String, schema: String) async throws -> String {
        if !jsonObjectOnly {
            let response = try await send(system: system, messages: messages, format: .schema(name: schemaName, schema: schema))
            // Schéma refusé : un seul nouvel essai en `json_object`, schéma recopié dans le prompt (§5.4).
            // Tout 400 compte : le texte de l'erreur varie selon le fournisseur.
            if response.status == 400 {
                jsonObjectOnly = true
            } else {
                return try content(response)
            }
        }
        let withSchema = system + "\n\nSCHÉMA JSON À RESPECTER :\n" + schema
        return try content(try await send(system: withSchema, messages: messages, format: .jsonObject))
    }

    private enum Format {
        case schema(name: String, schema: String)
        case jsonObject
    }

    private func send(system: String, messages: [LLMMessage], format: Format) async throws -> HTTPResponse {
        let responseFormat: [String: Any]
        switch format {
        case let .schema(name, schema):
            let parsed = try JSONSerialization.jsonObject(with: Data(schema.utf8))
            responseFormat = ["type": "json_schema", "json_schema": ["name": name, "strict": true, "schema": parsed]]
        case .jsonObject:
            responseFormat = ["type": "json_object"]
        }
        let all = [LLMMessage(role: "system", content: system)] + messages
        let body: [String: Any] = [
            "model": provider.model,
            "temperature": 0.4,
            "messages": all.map { ["role": $0.role, "content": $0.content] },
            "response_format": responseFormat,
        ]
        let request = HTTPRequest(
            method: "POST", url: provider.baseURL.appendingPathComponent("chat/completions"),
            headers: ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: body))
        do {
            return try await http.send(request)
        } catch {
            throw LLMError.network
        }
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
