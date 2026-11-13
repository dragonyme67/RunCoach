import Foundation
import Security
import RunCoachCore

/// Jetons Garmin dans le Keychain de l'iPhone (jamais dans UserDefaults, un fichier ou un journal).
/// `AfterFirstUnlock` : lisibles par la synchro en arrière-plan, téléphone verrouillé.
struct KeychainTokenStore: TokenStore {
    private let service = "local.runcoach.garmin"

    func read(_ key: String) -> String? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ key: String, _ value: String?) {
        guard let value else {
            SecItemDelete(base(key) as CFDictionary)
            return
        }
        // Mise à jour sur place plutôt que suppression puis ajout : un arrêt entre les deux perdrait le jeton.
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(base(key) as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(base(key).merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    private func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
}
