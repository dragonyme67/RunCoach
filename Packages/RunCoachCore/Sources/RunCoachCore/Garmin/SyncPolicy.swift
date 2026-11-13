import Foundation

/// Règles de la synchro Garmin (ARCHITECTURE.md §4.3, §5.1.6). Pures et testées : `SyncEngine` (app) les applique.
public enum SyncPolicy {
    /// Une synchro à l'ouverture de l'app seulement si la dernière date de plus de 15 min.
    public static let staleAfterS: TimeInterval = 15 * 60
    /// Taille d'une page de la liste d'activités.
    public static let pageSize = 100
    /// Fenêtre des métriques quotidiennes (sommeil, FC de repos, VO2max, statut).
    public static let metricWindowDays = 28
    /// Essais au plus pour les détails d'une activité, puis `failed`.
    public static let maxDetailAttempts = 3

    /// Requêtes autorisées pour un passage.
    /// Premier import (demande de l'utilisateur, 2026-11-13 : « récupérer toutes les données ») : sans plafond,
    /// app ouverte, une requête par seconde, reprise là où il s'est arrêté. Ensuite : 40 au premier plan,
    /// 20 en arrière-plan (iOS laisse environ 30 s).
    public static func budget(background: Bool, backfillDone: Bool) -> Int {
        if background { return 20 }
        return backfillDone ? 40 : Int.max
    }

    /// Date avant laquelle plus aucun appel à Garmin n'est permis, ou `nil` si l'erreur n'impose pas d'attente.
    /// `failures` = échecs consécutifs avant celui-ci.
    public static func nextAllowedCall(after error: GarminError, failures: Int, now: Date) -> Date? {
        switch error {
        case .rateLimited:
            let minutes = min(15 * pow(2, Double(min(failures, 10))), 24 * 60)
            return now.addingTimeInterval(minutes * 60)
        case .blocked:
            return now.addingTimeInterval(60 * 60)
        default:
            return nil
        }
    }

    /// Jours de métriques à demander, du plus récent au plus ancien : aujourd'hui et hier toujours
    /// (encore incomplets), puis les jours de la fenêtre absents de la base.
    public static func metricDays(today: Date, existing: Set<String>) -> [String] {
        (0..<metricWindowDays).compactMap { offset in
            let day = DayKey.key(DayKey.addDays(-offset, to: today))
            return offset < 2 || !existing.contains(day) ? day : nil
        }
    }
}
