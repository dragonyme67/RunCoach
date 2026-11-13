import Foundation

/// Charge d'entraînement (ARCHITECTURE.md §6.3) : méthode d'Edwards, aiguë sur 7 jours, chronique sur 28.
public enum LoadModel {
    /// Σ minutes en zone i × i ; sans zones connues : durée en minutes × 2.
    public static func edwardsLoad(_ run: RunSummary) -> Double {
        guard run.hrZoneSeconds.count == 5, run.hrZoneSeconds.contains(where: { $0 > 0 }) else {
            return run.durationS / 60 * 2
        }
        return run.hrZoneSeconds.enumerated().reduce(0) { $0 + $1.element / 60 * Double($1.offset + 1) }
    }

    public struct Load: Equatable, Sendable {
        public var acute: Double
        /// Moyenne hebdomadaire sur 28 jours.
        public var chronic: Double
        /// aiguë / chronique ; nil avant 3 semaines de données.
        public var ratio: Double?
    }

    public static func load(_ runs: [RunSummary], today: Date) -> Load {
        let end = DayKey.addDays(1, to: DayKey.calendar.startOfDay(for: today))
        func sum(days: Int) -> Double {
            let start = DayKey.addDays(-days, to: end)
            return runs.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + edwardsLoad($1) }
        }
        let acute = sum(days: 7)
        let chronic = sum(days: 28) / 4
        let first = runs.map(\.date).min()
        let enoughData = first.map { $0 <= DayKey.addDays(-21, to: end) } ?? false
        return Load(acute: acute, chronic: chronic, ratio: enoughData && chronic > 0 ? acute / chronic : nil)
    }
}
