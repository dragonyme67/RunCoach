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

extension CoachSchemas {
    /// Réponse du chat avec modifications du plan (§5.3.2) : questions d'entraînement, de plan ou de santé.
    public static var chatWithActions: String {
        #"""
        {"type":"object","additionalProperties":false,"required":["reply","actions","profile_patch","safety"],
         "properties":{"reply":{"type":"string"},
                       "actions":{"type":"array","items":{"type":"object","additionalProperties":false,
                                  "required":["op","date","new_date","workout"],
                                  "properties":{"op":{"type":"string","enum":["add","replace","remove","move"]},
                                                "date":{"type":"string"},"new_date":{"type":["string","null"]},
                                                "workout":{"anyOf":[\#(workout),{"type":"null"}]}}}},
                       "profile_patch":{"type":"object","additionalProperties":false,
                                        "required":["current_pain","pain_level","fatigue_level","injury_note","training_preference"],
                                        "properties":{"current_pain":{"type":["boolean","null"]},"pain_level":{"type":["string","null"]},
                                                      "fatigue_level":{"type":["string","null"]},
                                                      "injury_note":{"type":["string","null"]},
                                                  "training_preference":{"type":["string","null"]}}},
                       "safety":{"type":"string","enum":["none","pain","medical"]}}}
        """#
    }

    /// Réponse du chat pour un simple échange, sans modification du plan (schéma plus court, moins de jetons).
    public static let chat = #"""
    {"type":"object","additionalProperties":false,"required":["reply","profile_patch","safety"],
     "properties":{"reply":{"type":"string"},
                   "profile_patch":{"type":"object","additionalProperties":false,
                                    "required":["current_pain","pain_level","fatigue_level","injury_note","training_preference"],
                                    "properties":{"current_pain":{"type":["boolean","null"]},"pain_level":{"type":["string","null"]},
                                                  "fatigue_level":{"type":["string","null"]},
                                                  "injury_note":{"type":["string","null"]},
                                                  "training_preference":{"type":["string","null"]}}},
                   "safety":{"type":"string","enum":["none","pain","medical"]}}}
    """#
}

/// Réponse de l'IA dans le chat.
public struct ChatResponse: Codable, Equatable, Sendable {
    public struct ProfilePatch: Codable, Equatable, Sendable {
        public var currentPain: Bool?
        /// `mild` ou `severe`, toute autre valeur est ignorée.
        public var painLevel: String?
        /// `low` / `normal` / `high`, toute autre valeur est ignorée.
        public var fatigueLevel: String?
        public var injuryNote: String?
        /// Consigne durable de l'athlète (« course 4 min / marche 1 min ») ; chaîne vide = l'effacer.
        public var trainingPreference: String?

        enum CodingKeys: String, CodingKey {
            case currentPain = "current_pain", painLevel = "pain_level", fatigueLevel = "fatigue_level", injuryNote = "injury_note"
            case trainingPreference = "training_preference"
        }

        public init(currentPain: Bool? = nil, fatigueLevel: String? = nil, injuryNote: String? = nil) {
            self.currentPain = currentPain
            self.fatigueLevel = fatigueLevel
            self.injuryNote = injuryNote
        }
    }

    public var reply: String
    /// Modifications proposées ; absentes du schéma des échanges simples, donc vides par défaut.
    public var actions: [PlanAction]
    public var profilePatch: ProfilePatch
    /// `none` / `pain` / `medical`
    public var safety: String

    enum CodingKeys: String, CodingKey {
        case reply, actions, profilePatch = "profile_patch", safety
    }

    public init(reply: String, actions: [PlanAction] = [], profilePatch: ProfilePatch = .init(), safety: String = "none") {
        self.reply = reply
        self.actions = actions
        self.profilePatch = profilePatch
        self.safety = safety
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reply = try c.decode(String.self, forKey: .reply)
        actions = try c.decodeIfPresent([PlanAction].self, forKey: .actions) ?? []
        profilePatch = try c.decodeIfPresent(ProfilePatch.self, forKey: .profilePatch) ?? .init()
        safety = try c.decodeIfPresent(String.self, forKey: .safety) ?? "none"
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
