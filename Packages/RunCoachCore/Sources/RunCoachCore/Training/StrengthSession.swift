import Foundation

/// Déroulé d'une séance de renfo guidée dans l'app (étape 7, n° 4) : chaque série, puis son repos.
/// Pas de repos après la toute dernière série : la séance est finie.
public enum StrengthSession {
    public struct Phase: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// Série en répétitions : terminée quand l'athlète la valide.
            case reps(Int)
            /// Série en temps (gainage), décomptée.
            case timed(seconds: Int)
            /// Repos décompté avant la série suivante.
            case rest(seconds: Int)
        }

        public var exerciseId: String
        public var set: Int
        public var sets: Int
        public var kind: Kind
        public var note: String?
    }

    public static func phases(_ exercises: [StrengthExercise]) -> [Phase] {
        var out: [Phase] = []
        for (e, exercise) in exercises.enumerated() {
            let sets = max(1, exercise.sets)
            for set in 1...sets {
                let work: Phase.Kind
                if let reps = exercise.reps, reps > 0 {
                    work = .reps(reps)
                } else {
                    work = .timed(seconds: max(1, exercise.durationS ?? 30))
                }
                out.append(Phase(exerciseId: exercise.exerciseId, set: set, sets: sets, kind: work, note: exercise.note))
                let isLast = e == exercises.count - 1 && set == sets
                if !isLast, exercise.restS > 0 {
                    out.append(Phase(exerciseId: exercise.exerciseId, set: set, sets: sets, kind: .rest(seconds: exercise.restS)))
                }
            }
        }
        return out
    }
}
