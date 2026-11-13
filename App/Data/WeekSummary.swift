import Foundation
import RunCoachCore

/// Résumé de la semaine (lundi à dimanche) qui contient une date : jours, km prévus, km faits.
struct WeekSummary {
    struct Day: Identifiable {
        let id: String
        let date: Date
        let letter: String
        let isToday: Bool
        let kind: WorkoutKind?
        let status: String?
    }

    let days: [Day]
    let plannedKm: Double
    let doneKm: Double

    var progress: Double {
        plannedKm > 0 ? doneKm / plannedKm : 0
    }

    init(date: Date, workouts: [PlannedWorkout], runs: [Run]) {
        let start = DayKey.weekStart(date)
        // Le jour en surbrillance reste aujourd'hui, même en affichant une autre semaine.
        let todayKey = DayKey.key(Date())
        let letters = ["L", "M", "M", "J", "V", "S", "D"]
        var days: [Day] = []
        var keys = Set<String>()
        for i in 0..<7 {
            let dayDate = DayKey.addDays(i, to: start)
            let key = DayKey.key(dayDate)
            keys.insert(key)
            let workout = workouts.first { $0.dayKey == key && $0.status != "cancelled" }
            days.append(Day(
                id: key,
                date: dayDate,
                letter: letters[i],
                isToday: key == todayKey,
                kind: workout?.kindValue,
                status: workout?.status
            ))
        }
        self.days = days
        self.plannedKm = workouts
            .filter { keys.contains($0.dayKey) && $0.status != "cancelled" }
            .reduce(0) { $0 + ($1.estimatedDistanceKm ?? 0) }
        self.doneKm = runs
            .filter { keys.contains($0.dayKey) }
            .reduce(0) { $0 + $1.distanceM / 1000 }
    }
}
