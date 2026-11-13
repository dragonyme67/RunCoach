import Foundation

/// Stockage des secrets : Keychain dans l'app, mémoire dans les tests.
public protocol TokenStore: Sendable {
    func read(_ key: String) -> String?
    /// `nil` efface la valeur.
    func write(_ key: String, _ value: String?)
}
