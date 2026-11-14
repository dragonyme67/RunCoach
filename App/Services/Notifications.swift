import Foundation
import SwiftData
import UserNotifications
import RunCoachCore

/// Notifications locales (étape 6.1) : séance du jour à l'heure choisie, point du dimanche soir, et rappel deux jours
/// avant l'expiration de la signature de l'app. Locales seulement : un identifiant Apple gratuit n'a pas de push.
/// Reprogrammées à chaque passage de l'app en arrière-plan (le plan a pu changer) et à chaque changement de réglage.
/// Elles ne survivent pas à l'expiration de la signature (§8, risques de l'étape 6).
enum Notifications {
    static let enabledKey = "notifications.enabled"
    /// Heure du rappel de séance, en minutes depuis minuit.
    static let minuteKey = "notifications.minute"
    static let defaultMinute = 7 * 60 + 30

    /// Date d'expiration de la signature de l'app installée, si le profil est lisible.
    static var signatureExpiry: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return SigningProfile.expirationDate(data)
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    @MainActor
    static func reschedule(context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return }
        let minute = defaults.object(forKey: minuteKey) as? Int ?? defaultMinute
        let now = Date()
        let calendar = Calendar.current

        // Séance du jour : les 7 prochains jours suffisent, l'app est rouverte bien avant.
        let workouts = ((try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? []).filter { $0.status == "planned" }
        for offset in 0..<7 {
            let day = DayKey.addDays(offset, to: now)
            let key = DayKey.key(day)
            let planned = workouts.filter { $0.dayKey == key }
            guard !planned.isEmpty else { continue }
            var when = calendar.dateComponents([.year, .month, .day], from: day)
            when.hour = minute / 60
            when.minute = minute % 60
            guard let fire = calendar.date(from: when), fire > now else { continue }
            let body = planned.map { w in
                var parts = [w.title, "\(w.estimatedDurationMin) min"]
                if let km = w.estimatedDistanceKm { parts.append(Fmt.km(km * 1000, decimals: 1) + " km") }
                return parts.joined(separator: " · ")
            }.joined(separator: "\n")
            await add(center, id: "workout-\(key)", title: "Séance du jour", body: body,
                      trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
        }

        // Dimanche 19 h, chaque semaine.
        await add(center, id: "weekly", title: "Fin de semaine",
                  body: "Fais le point sur ta semaine et regarde celle qui arrive.",
                  trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 19, minute: 0, weekday: 1), repeats: true))

        // Deux jours avant l'expiration de la signature, à 18 h.
        if let expiry = signatureExpiry {
            var when = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: -2, to: expiry) ?? expiry)
            when.hour = 18
            if let fire = calendar.date(from: when), fire > now {
                await add(center, id: "expiry", title: "RunCoach expire dans 2 jours",
                          body: "Réinstalle-la avec Sideloadly par-dessus l'app : tes données sont gardées.",
                          trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            }
        }
    }

    @MainActor
    private static func add(_ center: UNUserNotificationCenter, id: String, title: String, body: String,
                            trigger: UNNotificationTrigger) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
