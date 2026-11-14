import Foundation

/// `WorkoutSpec` → corps de `POST /workout-service/workout` (ARCHITECTURE.md §5.3.3).
/// Format de course validé sur la Forerunner 745 le 2026-11-13 (tâche 2.0) ; bouton Lap, cible cardiaque et renfo
/// repris de `garminconnect/workout.py` (0.3.20), pas encore vus sur la montre.
public enum GarminWorkoutMapper {
    /// Préfixe de tous les workouts créés par l'app : c'est lui qui permet de les retrouver et de les nettoyer.
    public static let namePrefix = "RC · "

    public static func body(_ spec: WorkoutSpec) -> Data {
        let sport: [String: Any] = spec.kind == .strength
            ? ["sportTypeId": 5, "sportTypeKey": "strength_training", "displayOrder": 5]
            : ["sportTypeId": 1, "sportTypeKey": "running", "displayOrder": 1]
        // Compteur global : les étapes d'une répétition suivent le numéro du groupe.
        var order = 0
        func next() -> Int { order += 1; return order }

        var steps: [[String: Any]] = []
        if spec.kind == .strength {
            for exercise in spec.exercises {
                let group = next()
                let garmin = StrengthCatalog.garmin[exercise.exerciseId] ?? (category: "CORE", name: "")
                var work: [String: Any]
                if let reps = exercise.reps {
                    work = step(next(), type: 3, "interval", end: repsEnd(), value: Double(reps))
                } else if let seconds = exercise.durationS {
                    work = step(next(), type: 3, "interval", end: end(.time), value: Double(seconds))
                } else {
                    work = step(next(), type: 3, "interval", end: end(.lapButton), value: nil)
                }
                work["category"] = garmin.category
                work["exerciseName"] = garmin.name
                if let note = exercise.note { work["description"] = note }
                let rest = step(next(), type: 5, "rest", end: end(.time), value: Double(exercise.restS))
                steps.append(repeatGroup(group, count: max(1, exercise.sets), [work, rest]))
            }
        } else {
            for block in spec.blocks {
                if block.repeatCount > 1 {
                    let group = next()
                    let inner = block.steps.map { runStep($0, order: next()) }
                    steps.append(repeatGroup(group, count: block.repeatCount, inner))
                } else {
                    steps += block.steps.map { runStep($0, order: next()) }
                }
            }
        }
        // Garmin refuse un workout vide : une étape libre, terminée au bouton Lap.
        if steps.isEmpty { steps.append(step(next(), type: 3, "interval", end: end(.lapButton), value: nil)) }

        let workout: [String: Any] = [
            "workoutName": namePrefix + spec.title,
            "description": spec.rationale,
            "sportType": sport,
            "estimatedDurationInSecs": spec.estimatedDurationMin * 60,
            "workoutSegments": [["segmentOrder": 1, "sportType": sport, "workoutSteps": steps]],
        ]
        return (try? JSONSerialization.data(withJSONObject: workout, options: [.sortedKeys])) ?? Data()
    }

    private static func runStep(_ s: WorkoutStep, order: Int) -> [String: Any] {
        let type: (Int, String) = {
            switch s.intent {
            case .warmup: return (1, "warmup")
            case .cooldown: return (2, "cooldown")
            case .run: return (3, "interval")
            case .recover: return (4, "recovery")
            case .rest: return (5, "rest")
            }
        }()
        var out = step(order, type: type.0, type.1, end: end(s.end), value: s.end == .lapButton ? nil : s.value)
        switch s.target.type {
        case .pace:
            if let fast = s.target.minSPerKm, let slow = s.target.maxSPerKm, fast > 0, slow > 0 {
                // Garmin attend des m/s : valeur basse = borne lente.
                let speeds = [1000 / Double(slow), 1000 / Double(fast)].map { ($0 * 10_000).rounded() / 10_000 }
                out["targetType"] = ["workoutTargetTypeId": 6, "workoutTargetTypeKey": "pace.zone", "displayOrder": 6]
                out["targetValueOne"] = speeds.min()!
                out["targetValueTwo"] = speeds.max()!
            }
        case .hrZone:
            if let zone = s.target.hrZone, (1...5).contains(zone) {
                out["targetType"] = ["workoutTargetTypeId": 4, "workoutTargetTypeKey": "heart.rate.zone", "displayOrder": 4]
                out["zoneNumber"] = zone
            }
        case .none:
            break
        }
        if let note = s.note { out["description"] = note }
        return out
    }

    private static func step(_ order: Int, type id: Int, _ key: String, end: [String: Any], value: Double?) -> [String: Any] {
        var out: [String: Any] = [
            "type": "ExecutableStepDTO",
            "stepOrder": order,
            "stepType": ["stepTypeId": id, "stepTypeKey": key, "displayOrder": id],
            "endCondition": end,
            "targetType": ["workoutTargetTypeId": 1, "workoutTargetTypeKey": "no.target", "displayOrder": 1],
        ]
        // Entier quand c'est possible : 600 et non 600.0, comme dans le corps validé sur la montre.
        if let value {
            let number: Any = value == value.rounded() ? Int(value) : value
            out["endConditionValue"] = number
        }
        return out
    }

    private static func repeatGroup(_ order: Int, count: Int, _ steps: [[String: Any]]) -> [String: Any] {
        [
            "type": "RepeatGroupDTO",
            "stepOrder": order,
            "stepType": ["stepTypeId": 6, "stepTypeKey": "repeat", "displayOrder": 6],
            "numberOfIterations": count,
            "endCondition": ["conditionTypeId": 7, "conditionTypeKey": "iterations", "displayOrder": 7, "displayable": false],
            "endConditionValue": count,
            "smartRepeat": false,
            "workoutSteps": steps,
        ]
    }

    private static func end(_ end: StepEnd) -> [String: Any] {
        switch end {
        case .lapButton: return ["conditionTypeId": 1, "conditionTypeKey": "lap.button", "displayOrder": 1, "displayable": true]
        case .time: return ["conditionTypeId": 2, "conditionTypeKey": "time", "displayOrder": 2, "displayable": true]
        case .distance: return ["conditionTypeId": 3, "conditionTypeKey": "distance", "displayOrder": 3, "displayable": true]
        }
    }

    private static func repsEnd() -> [String: Any] {
        ["conditionTypeId": 10, "conditionTypeKey": "reps", "displayOrder": 10, "displayable": true]
    }
}
