import Foundation

/// Semaine de secours, sans IA (ARCHITECTURE.md §6.4) : gabarits qui respectent les garde-fous par construction.
/// L'app enregistre ces séances avec `source = fallback`.
public enum FallbackPlanner {
    public static func week(brief: WeekBrief, snapshot: AthleteSnapshot, raceDay: String? = nil,
                            raceDistanceKm: Double? = nil) -> [WorkoutSpec] {
        // Douleur : repos complet (G11 n'autorise que de la récupération courte, le repos est plus sûr).
        guard snapshot.athlete.pain != "severe" else { return [] }
        let easy = Guardrails.easyPaceSPerKm(snapshot)
        let tired = snapshot.athlete.needsReducedLoad
        let recent = snapshot.lastWeeks.suffix(3)

        var budget = min(brief.targetKm, brief.maxKm) * (tired ? 0.8 : 1)
        if let vmax = recent.map(\.km).max() { budget = min(budget, max(1.10 * vmax, vmax + 2)) }

        var out: [WorkoutSpec] = []
        var hardDays: Set<String> = []
        var free = brief.availableDays.filter { $0 != raceDay }

        if let raceDay, let km = raceDistanceKm, brief.allowedKinds.contains(.race) {
            out.append(race(day: raceDay, distanceKm: km, easyPaceSPerKm: easy))
            hardDays.insert(raceDay)
        }

        var sessions = brief.runSessions - out.count
        var remaining = budget

        // Sortie longue, le jour prévu.
        if sessions > 0, let day = brief.longRunDay, free.contains(day), brief.allowedKinds.contains(.long),
           let zone = snapshot.pace(.long), brief.longRunKm.count == 2 {
            // 45 % et non 50 % (G3) : les footings arrondis à la minute inférieure font un total un peu sous le budget.
            var km = min(brief.longRunKm[1], 0.45 * budget)
            if let longest = recent.map(\.longestKm).max() { km = min(km, longest + 2) }
            km = (km * 10).rounded(.down) / 10
            if km >= 1 {
                out.append(spec(day, .long, "Sortie longue", "Allonger la distance pas à pas, toujours à allure facile.",
                                [WorkoutBlock(steps: [WorkoutStep(intent: .run, end: .distance, value: km * 1000,
                                                                  target: .pace(zone.fastSPerKm, zone.slowSPerKm))])], easy))
                hardDays.insert(day)
                free.removeAll { $0 == day }
                sessions -= 1
                remaining -= km
            }
        }

        // Une séance tempo courte, si le brief l'autorise, un jour non voisin d'un jour dur.
        if sessions > 0, !tired, brief.maxQualitySessions > 0, brief.allowedKinds.contains(.tempo), let zone = snapshot.pace(.tempo),
           let day = free.first(where: { d in !hardDays.contains(Guardrails.nextDay(d)) && !hardDays.contains(previousDay(d)) }) {
            let median = Double(zone.fastSPerKm + zone.slowSPerKm) / 2
            let workKm = 0.9 * max(2, 0.10 * brief.targetKm)
            let repMin = min(10, (workKm * median / 2 / 60).rounded(.down))
            let blocks = [
                WorkoutBlock(steps: [WorkoutStep(intent: .warmup, end: .time, value: 600, note: "Très facile")]),
                WorkoutBlock(repeatCount: 2, steps: [
                    WorkoutStep(intent: .run, end: .time, value: repMin * 60, target: .pace(zone.fastSPerKm, zone.slowSPerKm)),
                    WorkoutStep(intent: .recover, end: .time, value: 120, note: "Trot léger"),
                ]),
                WorkoutBlock(steps: [WorkoutStep(intent: .cooldown, end: .time, value: 600)]),
            ]
            let tempo = spec(day, .tempo, "Tempo 2 × \(Int(repMin)) min", "Travail au seuil, court et contrôlé : soutenu mais pas à fond.",
                             blocks, easy)
            let km = Guardrails.distanceKm(tempo, easyPaceSPerKm: easy)
            if repMin >= 3, km <= remaining, Double(tempo.estimatedDurationMin) <= Double(brief.maxSessionMin) {
                out.append(tempo)
                hardDays.insert(day)
                free.removeAll { $0 == day }
                sessions -= 1
                remaining -= km
            }
        }

        // Footings faciles pour le reste du volume.
        let easyDays = Array(free.prefix(max(0, sessions)))
        if !easyDays.isEmpty, let zone = snapshot.pace(.easy) {
            let minutes = min(Double(brief.maxSessionMin), (remaining / Double(easyDays.count) * easy / 60).rounded(.down))
            if minutes >= 10 {
                for day in easyDays {
                    out.append(spec(day, .easy, "Footing facile", "Endurance de base à allure confortable : tu dois pouvoir parler.",
                                    [WorkoutBlock(steps: [WorkoutStep(intent: .run, end: .time, value: minutes * 60,
                                                                      target: .pace(zone.fastSPerKm, zone.slowSPerKm))])], easy))
                }
            }
        }

        // Renforcement, sans prendre les jours de repos obligatoires ni la veille d'un jour dur.
        let restNeeded = snapshot.athlete.isBeginner ? 2 : 1
        let used = Set(out.map(\.date)).count
        let hard = Set(out.filter { $0.kind.isHard }.map(\.date))
        let strengthDays = brief.strengthDays.filter { !hard.contains(Guardrails.nextDay($0)) && !out.map(\.date).contains($0) }
        for day in strengthDays.prefix(max(0, min(brief.strengthSessions, 7 - restNeeded - used))) {
            out.append(spec(day, .strength, "Renfo coureur", "Fessiers, mollets et gainage : ce qui protège tes articulations.", [], easy,
                            exercises: [
                                StrengthExercise(exerciseId: "squat", sets: 3, reps: 12, restS: 45),
                                StrengthExercise(exerciseId: "glute_bridge", sets: 3, reps: 15, restS: 45),
                                StrengthExercise(exerciseId: "calf_raise", sets: 3, reps: 15, restS: 45),
                                StrengthExercise(exerciseId: "plank", sets: 3, durationS: 40, restS: 45),
                            ]))
        }
        return out.sorted { $0.date < $1.date }
    }

    /// La course elle-même, posée par le code (jamais par l'IA).
    public static func race(day: String, distanceKm: Double, easyPaceSPerKm: Double) -> WorkoutSpec {
        spec(day, .race, "Course", "Le jour J : pars prudemment, accélère sur la fin si tout va bien.",
             [WorkoutBlock(steps: [WorkoutStep(intent: .run, end: .distance, value: distanceKm * 1000)])], easyPaceSPerKm)
    }

    private static func previousDay(_ key: String) -> String {
        DayKey.date(key).map { DayKey.key(DayKey.addDays(-1, to: $0)) } ?? key
    }

    private static func spec(_ date: String, _ kind: WorkoutKind, _ title: String, _ rationale: String, _ blocks: [WorkoutBlock],
                             _ easy: Double, exercises: [StrengthExercise] = []) -> WorkoutSpec {
        var w = WorkoutSpec(date: date, kind: kind, title: title, rationale: rationale, estimatedDurationMin: 0,
                            estimatedDistanceKm: nil, blocks: blocks, exercises: exercises)
        w.estimatedDurationMin = Int(Guardrails.durationMin(w, easyPaceSPerKm: easy).rounded())
        if kind.isRun { w.estimatedDistanceKm = (Guardrails.distanceKm(w, easyPaceSPerKm: easy) * 10).rounded() / 10 }
        return w
    }
}
