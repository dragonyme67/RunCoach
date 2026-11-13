import Foundation

/// Rattachement du réalisé au prévu (ARCHITECTURE.md §4.3) : une sortie est rattachée à la séance encore prévue
/// du même jour local et du même genre (course ou renfo) ; une séance encore prévue après la fin de son jour est manquée.
public enum WorkoutMatcher {
    public struct Planned: Sendable {
        public var dayKey: String
        public var isRun: Bool
        /// `planned` / `done` / `missed` / `skipped` / `cancelled`
        public var status: String

        public init(dayKey: String, isRun: Bool, status: String) {
            self.dayKey = dayKey
            self.isRun = isRun
            self.status = status
        }
    }

    public struct Done: Sendable {
        public var dayKey: String
        public var isRun: Bool

        public init(dayKey: String, isRun: Bool) {
            self.dayKey = dayKey
            self.isRun = isRun
        }
    }

    /// Indices des paires (prévu, réalisé) à rattacher et des séances manquées.
    /// `done` : seulement les activités pas encore rattachées.
    public static func match(planned: [Planned], done: [Done], todayKey: String) -> (pairs: [(planned: Int, done: Int)], missed: [Int]) {
        var pairs: [(planned: Int, done: Int)] = []
        var usedDone: Set<Int> = []
        var matched: Set<Int> = []
        for (p, workout) in planned.enumerated() where workout.status == "planned" {
            if let d = done.indices.first(where: { !usedDone.contains($0) && done[$0].dayKey == workout.dayKey && done[$0].isRun == workout.isRun }) {
                pairs.append((p, d))
                usedDone.insert(d)
                matched.insert(p)
            }
        }
        let missed = planned.indices.filter { !matched.contains($0) && planned[$0].status == "planned" && planned[$0].dayKey < todayKey }
        return (pairs, missed)
    }
}
