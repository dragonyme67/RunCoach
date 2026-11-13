import Foundation

/// Modification du plan proposée par le chat (ARCHITECTURE.md §5.3.2, §6.6). Appliquée seulement après confirmation.
public struct PlanAction: Codable, Equatable, Sendable {
    public enum Op: String, Codable, Sendable {
        case add, replace, remove, move
    }

    public var op: Op
    public var date: String
    /// Requis pour `move`.
    public var newDate: String?
    /// Requis pour `add` et `replace`.
    public var workout: WorkoutSpec?

    enum CodingKeys: String, CodingKey {
        case op, date, newDate = "new_date", workout
    }

    public init(op: Op, date: String, newDate: String? = nil, workout: WorkoutSpec? = nil) {
        self.op = op
        self.date = date
        self.newDate = newDate
        self.workout = workout
    }
}

public enum PlanActions {
    public struct Outcome: Sendable {
        /// Les séances après application.
        public var specs: [WorkoutSpec]
        /// Résumé lisible, une ligne par action (carte de confirmation).
        public var lines: [String]
        /// Actions impossibles ; vide si tout s'applique.
        public var problems: [String]
    }

    /// Applique les actions à une copie des séances. Seules les dates à partir d'aujourd'hui sont modifiables.
    public static func apply(_ actions: [PlanAction], to specs: [WorkoutSpec], todayKey: String) -> Outcome {
        var out = specs
        var lines: [String] = []
        var problems: [String] = []
        /// Séance visée à cette date : même genre (course ou renfo) que `kind` si on le connaît.
        func target(_ date: String, _ kind: WorkoutKind?) -> Int? {
            out.firstIndex { $0.date == date && (kind == nil || $0.kind.isRun == kind!.isRun) } ?? out.firstIndex { $0.date == date }
        }
        for action in actions {
            guard action.date >= todayKey, (action.newDate ?? todayKey) >= todayKey else {
                problems.append("\(action.op.rawValue) le \(action.date) : on ne modifie que les séances à venir")
                continue
            }
            switch action.op {
            case .add:
                guard var workout = action.workout else { problems.append("add le \(action.date) : séance manquante"); continue }
                workout.date = action.date
                out.append(workout)
                lines.append("Ajout \(label(action.date)) : \(workout.title)")
            case .replace:
                guard var workout = action.workout else { problems.append("replace le \(action.date) : séance manquante"); continue }
                guard let i = target(action.date, workout.kind) else { problems.append("replace le \(action.date) : aucune séance ce jour-là"); continue }
                workout.date = action.date
                lines.append("\(label(action.date).capitalized) : \(out[i].title) → \(workout.title)")
                out[i] = workout
            case .remove:
                guard let i = target(action.date, action.workout?.kind) else { problems.append("remove le \(action.date) : aucune séance ce jour-là"); continue }
                lines.append("Supprimée \(label(action.date)) : \(out[i].title)")
                out.remove(at: i)
            case .move:
                guard let newDate = action.newDate else { problems.append("move le \(action.date) : new_date manquant"); continue }
                guard let i = target(action.date, action.workout?.kind) else { problems.append("move le \(action.date) : aucune séance ce jour-là"); continue }
                lines.append("\(out[i].title) : \(label(action.date)) → \(label(newDate))")
                out[i].date = newDate
            }
        }
        return Outcome(specs: out.sorted { $0.date < $1.date }, lines: lines, problems: problems)
    }

    /// « mardi 17 novembre »
    static func label(_ key: String) -> String {
        guard let date = DayKey.date(key) else { return key }
        let formatter = DateFormatter()
        formatter.calendar = DayKey.calendar
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date)
    }
}
