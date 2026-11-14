import Foundation

/// Signature de l'app installée par Sideloadly : le profil `embedded.mobileprovision` du paquet porte sa date
/// d'expiration (7 jours avec un identifiant Apple gratuit). Le fichier est un plist enveloppé dans une signature
/// CMS : on lit le XML entre `<?xml` et `</plist>`, sans vérifier la signature (simple affichage, pas de sécurité).
public enum SigningProfile {
    public static func expirationDate(_ data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let xml = Data(data[start.lowerBound..<end.upperBound])
        let plist = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil)
        return (plist as? [String: Any])?["ExpirationDate"] as? Date
    }
}
