import Foundation

/// Ce que l'envoi sur la montre doit faire (flux F3, ARCHITECTURE.md §2.2). Le calendrier Garmin est un miroir des
/// séances encore prévues des 7 prochains jours : tout autre workout « RC · » (séance annulée, remplacée, déplacée,
/// passée, ou supprimée de la base) est supprimé chez Garmin. Une séance modifiée est donc supprimée puis recréée.
public enum WatchSync {
    public static let windowDays = 7
    public static let maxAttempts = 3

    public struct Local: Sendable {
        public var dayKey: String
        public var status: String
        public var garminWorkoutId: Int64?
        /// `notSent` / `sent` / `needsUpdate` / `failed`
        public var state: String
        public var attempts: Int

        public init(dayKey: String, status: String, garminWorkoutId: Int64?, state: String, attempts: Int) {
            self.dayKey = dayKey
            self.status = status
            self.garminWorkoutId = garminWorkoutId
            self.state = state
            self.attempts = attempts
        }
    }

    public struct Decision: Equatable, Sendable {
        /// Workouts à supprimer chez Garmin.
        public var delete: [Int64]
        /// Séances locales dont les identifiants Garmin sont à effacer.
        public var forget: [Int]
        /// Séances à créer puis planifier, dans l'ordre des dates.
        public var send: [Int]
    }

    public static func decide(local: [Local], remote: [WorkoutRefDTO], today: Date) -> Decision {
        let first = DayKey.key(today)
        let last = DayKey.key(DayKey.addDays(windowDays - 1, to: today))
        let remoteIds = remote.filter { $0.workoutName?.hasPrefix(GarminWorkoutMapper.namePrefix) == true }.compactMap(\.workoutId)
        let present = Set(remoteIds)
        let wanted = local.map { $0.status == "planned" && $0.dayKey >= first && $0.dayKey <= last }
        // Gardé : voulu, bien envoyé, et toujours chez Garmin (sinon l'utilisateur l'a supprimé : on le renvoie).
        let kept = Set(local.indices.filter {
            wanted[$0] && local[$0].state == "sent" && local[$0].garminWorkoutId.map(present.contains) == true
        })
        let keptIds = Set(kept.compactMap { local[$0].garminWorkoutId })
        return Decision(
            delete: remoteIds.filter { !keptIds.contains($0) },
            forget: local.indices.filter { local[$0].garminWorkoutId != nil && !kept.contains($0) },
            send: local.indices
                .filter { wanted[$0] && !kept.contains($0) && local[$0].attempts < maxAttempts }
                .sorted { local[$0].dayKey < local[$1].dayKey })
    }
}
