import Foundation
import SwiftData
import WidgetKit
import RunCoachCore

/// Écrit le résumé lu par les widgets dans le conteneur partagé (App Group) et les fait redessiner (étape 7, n° 11).
/// Sans App Group utilisable (installation qui ne l'a pas enregistré), rien n'est écrit : le widget invite à
/// ouvrir l'app.
enum WidgetBridge {
    @MainActor
    static func update(context: ModelContext) {
        let group = WidgetSnapshot.appGroup(info: Bundle.main.infoDictionary)
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
        let workouts = ((try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? []).filter { $0.status != "cancelled" }
        let runs = (try? context.fetch(FetchDescriptor<Run>())) ?? []
        let today = Date()
        let todayKey = DayKey.key(today)
        func session(_ w: PlannedWorkout) -> WidgetSnapshot.Session {
            .init(kind: w.kindValue, title: w.title, durationMin: w.estimatedDurationMin,
                  distanceKm: w.estimatedDistanceKm, done: w.status == "done")
        }
        let next = workouts.filter { $0.dayKey > todayKey && $0.status == "planned" }.min { $0.dayKey < $1.dayKey }
        let week = WeekSummary(date: today, workouts: workouts, runs: runs)
        let snapshot = WidgetSnapshot(day: todayKey, today: workouts.filter { $0.dayKey == todayKey }.map(session),
                                      next: next.map(session), nextDay: next?.dayKey,
                                      weekDoneKm: week.doneKm, weekPlannedKm: week.plannedKm)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: folder.appendingPathComponent(WidgetSnapshot.fileName), options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
