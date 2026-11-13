import Foundation

/// Schémas JSON envoyés dans `response_format` (ARCHITECTURE.md §5.3.2).
/// Écrits sans `$ref` : la documentation de Mistral ne dit pas s'il les accepte, le schéma déplié marche partout.
/// Le schéma est une aide côté fournisseur, pas une garantie : la réponse passe toujours par `Codable` et `Guardrails`.
public enum CoachSchemas {
    static let target = #"""
    {"type":"object","additionalProperties":false,"required":["type","min_s_per_km","max_s_per_km","hr_zone"],
     "properties":{"type":{"type":"string","enum":["none","pace","hr_zone"]},
                   "min_s_per_km":{"type":["integer","null"]},"max_s_per_km":{"type":["integer","null"]},
                   "hr_zone":{"type":["integer","null"]}}}
    """#

    static let step = #"""
    {"type":"object","additionalProperties":false,"required":["intent","end","value","target","note"],
     "properties":{"intent":{"type":"string","enum":["warmup","run","recover","rest","cooldown"]},
                   "end":{"type":"string","enum":["time","distance","lap_button"]},
                   "value":{"type":["number","null"]},"target":\#(target),"note":{"type":["string","null"]}}}
    """#

    static let block = #"""
    {"type":"object","additionalProperties":false,"required":["repeat","steps"],
     "properties":{"repeat":{"type":"integer"},"steps":{"type":"array","items":\#(step)}}}
    """#

    static var exercise: String {
        let ids = StrengthCatalog.ids.map { "\"\($0)\"" }.joined(separator: ",")
        return #"""
        {"type":"object","additionalProperties":false,"required":["exercise_id","sets","reps","duration_s","rest_s","note"],
         "properties":{"exercise_id":{"type":"string","enum":[\#(ids)]},"sets":{"type":"integer"},
                       "reps":{"type":["integer","null"]},"duration_s":{"type":["integer","null"]},
                       "rest_s":{"type":"integer"},"note":{"type":["string","null"]}}}
        """#
    }

    static var workout: String {
        #"""
        {"type":"object","additionalProperties":false,
         "required":["date","kind","title","rationale","estimated_duration_min","estimated_distance_km","blocks","exercises"],
         "properties":{"date":{"type":"string"},
                       "kind":{"type":"string","enum":["easy","long","tempo","intervals","recovery","strength","race"]},
                       "title":{"type":"string"},"rationale":{"type":"string"},
                       "estimated_duration_min":{"type":"integer"},"estimated_distance_km":{"type":["number","null"]},
                       "blocks":{"type":"array","items":\#(block)},"exercises":{"type":"array","items":\#(exercise)}}}
        """#
    }

    /// Réponse de génération d'une semaine (`WeekPlanResponse`).
    public static var weekPlan: String {
        #"""
        {"type":"object","additionalProperties":false,"required":["week_start","summary","workouts"],
         "properties":{"week_start":{"type":"string"},"summary":{"type":"string"},
                       "workouts":{"type":"array","items":\#(workout)}}}
        """#
    }
}

/// Réponse de l'IA pour une semaine.
public struct WeekPlanResponse: Codable, Equatable, Sendable {
    public var weekStart: String
    public var summary: String
    public var workouts: [WorkoutSpec]

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start", summary, workouts
    }

    public init(weekStart: String, summary: String, workouts: [WorkoutSpec]) {
        self.weekStart = weekStart
        self.summary = summary
        self.workouts = workouts
    }
}
