import Foundation

/// Cahier des charges d'une semaine (`WeekBrief`) à partir de la semaine du plan et du profil (ARCHITECTURE.md §6.2, §6.3).
public enum WeekBriefBuilder {
    public struct Input: Sendable {
        public var week: MacroWeek
        /// 1 = lundi … 7 = dimanche
        public var availableWeekdays: [Int]
        public var longRunWeekday: Int
        public var maxSessionMin: Int
        public var wantsStrength: Bool
        public var beginner: Bool
        /// Rapport charge aiguë / chronique, nil s'il n'est pas encore défini.
        public var loadRatio: Double?
        /// Km réellement courus la semaine précédente.
        public var lastWeekKm: Double
        /// Jour de la course si elle tombe dans cette semaine.
        public var raceDay: String?
        /// Gêne légère ou fatigue élevée : aucune séance intense, volume plafonné à 80 % (G11).
        public var reducedLoad = false

        public init(week: MacroWeek, availableWeekdays: [Int], longRunWeekday: Int, maxSessionMin: Int,
                    wantsStrength: Bool, beginner: Bool, loadRatio: Double?, lastWeekKm: Double, raceDay: String? = nil) {
            self.week = week
            self.availableWeekdays = availableWeekdays
            self.longRunWeekday = longRunWeekday
            self.maxSessionMin = maxSessionMin
            self.wantsStrength = wantsStrength
            self.beginner = beginner
            self.loadRatio = loadRatio
            self.lastWeekKm = lastWeekKm
            self.raceDay = raceDay
        }
    }

    public static func brief(_ input: Input) -> WeekBrief {
        let week = input.week
        guard let start = DayKey.date(week.weekStart) else {
            return WeekBrief(weekStart: week.weekStart, phase: week.phase, isCutback: week.isCutback, targetKm: 0, minKm: 0,
                             maxKm: 0, runSessions: 0, maxQualitySessions: 0, longRunKm: [0, 0], longRunDay: nil,
                             availableDays: [], maxSessionMin: input.maxSessionMin, strengthSessions: 0, strengthDays: [],
                             allowedKinds: [])
        }
        func day(_ weekday: Int) -> String { DayKey.key(DayKey.addDays(weekday - 1, to: start)) }

        var available = input.availableWeekdays.sorted().map(day)
        if let race = input.raceDay, !available.contains(race) { available = (available + [race]).sorted() }
        let hasLong = week.longRunKm > 0
        let longDay = hasLong && input.availableWeekdays.contains(input.longRunWeekday) ? day(input.longRunWeekday) : nil

        var notes: [String] = []
        var maxKm = (week.targetKm * 1.05 * 10).rounded() / 10
        if let ratio = input.loadRatio, ratio > 1.5 {
            maxKm = min(maxKm, input.lastWeekKm)
            notes.append("Charge récente très élevée : volume plafonné à celui de la semaine dernière.")
        } else if let ratio = input.loadRatio, ratio > 1.3 {
            notes.append("Charge récente élevée : reste prudent sur l'intensité.")
        }

        var quality = week.qualitySessions
        if input.reducedLoad {
            quality = 0
            maxKm = min(maxKm, (week.targetKm * 0.8 * 10).rounded() / 10)
            notes.append("Gêne ou fatigue déclarée : aucune séance intense, volume réduit de 20 %.")
        }
        if input.beginner && quality == 0 { notes.append("Débutant : pas de fractionné ni de tempo cette semaine.") }

        // Renfo : 1 séance en fondation, 2 en développement, 1 ensuite ; jamais la veille de la sortie longue.
        let strengthSessions: Int
        switch week.phase {
        case _ where !input.wantsStrength: strengthSessions = 0
        case .build: strengthSessions = 2
        case .race: strengthSessions = 0
        default: strengthSessions = 1
        }
        let dayBeforeLong = longDay.flatMap(DayKey.date).map { DayKey.key(DayKey.addDays(-1, to: $0)) }
        let strengthDays = (1...7).map(day).filter { !available.contains($0) && $0 != dayBeforeLong }

        var kinds: [WorkoutKind] = [.easy, .recovery]
        if hasLong { kinds.append(.long) }
        if quality > 0 { kinds += [.tempo, .intervals] }
        if strengthSessions > 0 { kinds.append(.strength) }
        if input.raceDay != nil { kinds.append(.race) }

        return WeekBrief(
            weekStart: week.weekStart, phase: week.phase, isCutback: week.isCutback,
            targetKm: week.targetKm, minKm: (week.targetKm * (input.reducedLoad ? 0.6 : 0.8) * 10).rounded() / 10, maxKm: maxKm,
            runSessions: min(week.sessions, available.count), maxQualitySessions: quality,
            longRunKm: [max(0, week.longRunKm - 1), week.longRunKm], longRunDay: longDay,
            availableDays: available, maxSessionMin: input.maxSessionMin,
            strengthSessions: min(strengthSessions, strengthDays.count), strengthDays: strengthDays,
            allowedKinds: kinds, notes: notes)
    }
}
