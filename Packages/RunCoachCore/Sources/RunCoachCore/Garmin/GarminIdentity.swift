import Foundation

/// Tout ce qui identifie l'app auprès de Garmin (ARCHITECTURE.md §5.1.1).
/// Valeurs de `python-garminconnect` 0.3.20, validées sur le compte de l'utilisateur le 2026-11-13 (tâche 2.0).
public enum GarminIdentity {
    public static let serviceURL = "https://mobile.integration.garmin.com/gcm/ios"
    public static let signInURL = URL(string:
        "https://sso.garmin.com/mobile/sso/en_US/sign-in?clientId=GCM_IOS_DARK&service=https%3A%2F%2Fmobile.integration.garmin.com%2Fgcm%2Fios")!
    public static let tokenURL = URL(string: "https://diauth.garmin.com/di-oauth2-service/oauth/token")!
    public static let apiBase = URL(string: "https://connectapi.garmin.com")!
    public static let ticketGrantType = "https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket"

    /// Essayés dans l'ordre à l'échange du ticket. Le premier a été accepté lors de la validation 2.0.
    public static let diClientIds = [
        "GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2",
        "GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4",
        "GARMIN_CONNECT_MOBILE_ANDROID_DI",
        "GARMIN_CONNECT_MOBILE_IOS_DI",
    ]

    /// En-têtes des appels `diauth` et `connectapi` : ceux de la librairie, seuls validés en réel.
    public static let headers: [String: String] = [
        "User-Agent": "GCM-Android-5.23",
        "X-Garmin-User-Agent": "com.garmin.android.apps.connectmobile/5.23; ; Google/sdk_gphone64_arm64/google; Android/33; Dalvik/2.1.0",
        "X-Garmin-Paired-App-Version": "10861",
        "X-Garmin-Client-Platform": "Android",
        "X-App-Ver": "10861",
        "X-Lang": "en",
        "X-GCExperience": "GC5",
        "Accept-Language": "en-US,en;q=0.9",
    ]

    private static let ticketPattern = try! NSRegularExpression(
        pattern: #"(?:ticket=|serviceTicketId"\s*:\s*"|^)(ST-[A-Za-z0-9-]+)"#)

    /// Ticket de service trouvé dans une URL, un JSON de réponse ou le HTML d'une page de connexion.
    public static func ticket(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = ticketPattern.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
