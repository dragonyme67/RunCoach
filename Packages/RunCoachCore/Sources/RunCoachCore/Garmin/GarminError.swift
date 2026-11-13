import Foundation

public enum GarminError: Error, Equatable, Sendable {
    /// Session perdue : l'utilisateur doit se reconnecter. Jamais de reconnexion automatique.
    case needsLogin
    /// HTTP 427 ou 429 : arrêt immédiat, attente exponentielle (`SyncPolicy`).
    case rateLimited
    /// HTTP 403 : client ou réseau bloqué. Arrêt, attente d'une heure, pas de rafraîchissement.
    case blocked
    /// Pas de réponse (hors ligne, délai dépassé).
    case network
    /// Réponse illisible.
    case decoding
    case http(Int)
}
