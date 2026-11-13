import Foundation

/// Plan semaine par semaine jusqu'à la course : phases, volume, sortie longue, nombre de séances (ARCHITECTURE.md §6.3).
/// La règle de progression n'est jamais assouplie : si les semaines manquent, le plan s'arrête où elle mène.
public enum MacroPlanner {
    public struct Input: Sendable {
        /// Lundi de la première semaine du plan.
        public var startWeek: Date
        /// nil : objectif « forme », cycle de 12 semaines visant 1,5 × V0.
        public var raceDate: Date?
        public var raceDistanceKm: Double?
        /// Km moyens des 3 dernières semaines complètes (à défaut : séances × distance de la sortie de référence).
        public var v0Km: Double
        /// Plus longue sortie des 3 dernières semaines.
        public var l0Km: Double
        public var availableDays: Int
        /// Court depuis moins de 6 mois.
        public var beginner: Bool

        public init(startWeek: Date, raceDate: Date?, raceDistanceKm: Double?, v0Km: Double, l0Km: Double,
                    availableDays: Int, beginner: Bool) {
            self.startWeek = startWeek
            self.raceDate = raceDate
            self.raceDistanceKm = raceDistanceKm
            self.v0Km = v0Km
            self.l0Km = l0Km
            self.availableDays = availableDays
            self.beginner = beginner
        }
    }

    public static func plan(_ input: Input) -> [MacroWeek] {
        var raceKm: Double?
        var count = 12
        if let date = input.raceDate, let km = input.raceDistanceKm {
            raceKm = km
            let days = DayKey.calendar.dateComponents([.day], from: input.startWeek, to: DayKey.weekStart(date)).day ?? 0
            count = max(1, days / 7 + 1)
        }
        let peakKm = max(input.v0Km, min(raceKm.map { 1.8 * $0 } ?? 1.5 * input.v0Km, 45))

        var weeks: [MacroWeek] = []
        var volume = input.v0Km   // volume de la chaîne de progression, hors semaine allégée
        var long: Double?         // idem pour la sortie longue
        var maxVolume = 0.0, maxLong = 0.0
        for w in 0..<count {
            let phase = phase(week: w, count: count, isRace: raceKm != nil, beginner: input.beginner)
            var km: Double, longKm: Double, cutback = false
            switch phase {
            case .taper:
                km = 0.70 * (weeks.isEmpty ? input.v0Km : maxVolume)
                longKm = 0.6 * (weeks.isEmpty ? input.l0Km : maxLong)
            case .race:
                km = 0.40 * (weeks.isEmpty ? input.v0Km : maxVolume)
                longKm = 0
            case .base, .build, .peak:
                cutback = w % 4 == 3
                if cutback {
                    km = 0.75 * volume
                } else {
                    volume = min(peakKm, max(volume * 1.08, volume + 1.5))
                    km = volume
                }
                let cap = min(raceKm.map { 0.9 * $0 } ?? .infinity, 0.45 * km)
                let first = max(input.l0Km, 0.35 * km)
                if cutback {
                    longKm = min(cap, (long ?? first) - 2)
                } else {
                    let next = min(cap, long.map { $0 + 1 } ?? first)
                    long = next
                    longKm = next
                }
            }
            maxVolume = max(maxVolume, km)
            maxLong = max(maxLong, longKm)

            let sessions = max(2, min(input.availableDays, phase == .build || phase == .peak ? 4 : 3))
            var quality: Int
            switch phase {
            case .base: quality = input.beginner ? 0 : 1
            case .build, .taper: quality = 1
            case .peak: quality = sessions >= 4 ? 2 : 1
            case .race: quality = 0
            }
            if cutback { quality = min(quality, 1) }

            weeks.append(MacroWeek(weekStart: DayKey.key(DayKey.addDays(7 * w, to: input.startWeek)), phase: phase,
                                   targetKm: (km * 10).rounded() / 10, longRunKm: (max(0, longKm) * 10).rounded() / 10,
                                   sessions: sessions, qualitySessions: quality, isCutback: cutback))
        }
        return weeks
    }

    /// Depuis la fin : course, affûtage, 4 semaines de pic ; le reste moitié fondation, moitié développement,
    /// avec au moins 6 semaines de fondation pour un débutant (4 sinon).
    static func phase(week w: Int, count n: Int, isRace: Bool, beginner: Bool) -> TrainingPhase {
        guard isRace else { return w < 6 ? .base : .build }
        switch n - 1 - w {
        case 0: return .race
        case 1: return .taper
        case 2...5: return .peak
        default:
            let rest = n - 6
            let base = min(rest, max(beginner ? 6 : 4, (rest + 1) / 2))
            return w < base ? .base : .build
        }
    }
}
