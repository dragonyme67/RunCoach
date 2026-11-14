import Foundation

/// Ce que les widgets affichent (étape 7, n° 11), écrit par l'app dans le conteneur partagé (App Group) et lu par
/// l'extension : la séance du jour, la prochaine, et les km de la semaine. Ni tracé ni donnée de santé.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Session: Codable, Equatable, Sendable {
        public var kind: WorkoutKind
        public var title: String
        public var durationMin: Int
        public var distanceKm: Double?
        public var done: Bool

        public init(kind: WorkoutKind, title: String, durationMin: Int, distanceKm: Double?, done: Bool) {
            self.kind = kind
            self.title = title
            self.durationMin = durationMin
            self.distanceKm = distanceKm
            self.done = done
        }
    }

    /// Jour (`yyyy-MM-dd`) auquel le résumé a été écrit : un autre jour, le widget invite à ouvrir l'app.
    public var day: String
    public var today: [Session]
    public var next: Session?
    public var nextDay: String?
    public var weekDoneKm: Double
    public var weekPlannedKm: Double

    public init(day: String, today: [Session], next: Session?, nextDay: String?, weekDoneKm: Double, weekPlannedKm: Double) {
        self.day = day
        self.today = today
        self.next = next
        self.nextDay = nextDay
        self.weekDoneKm = weekDoneKm
        self.weekPlannedKm = weekPlannedKm
    }

    public static let fileName = "widget.json"
    public static let defaultAppGroup = "group.local.runcoach.app"

    /// Identifiant de l'App Group : SideStore (comme AltStore) renomme les groupes d'un compte gratuit et écrit les
    /// vrais noms dans la clé `ALTAppGroups` de l'Info.plist ; sans elle, le nom d'origine.
    public static func appGroup(info: [String: Any]?) -> String {
        (info?["ALTAppGroups"] as? [String])?.first ?? defaultAppGroup
    }

    public var weekProgress: Double { weekPlannedKm > 0 ? min(1, weekDoneKm / weekPlannedKm) : 0 }
}
