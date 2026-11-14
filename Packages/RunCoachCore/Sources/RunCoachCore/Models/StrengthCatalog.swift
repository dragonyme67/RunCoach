import Foundation

/// Catalogue fixe des exercices de renforcement (ARCHITECTURE.md §5.3.1).
/// shortcut: identifiants et équivalents Garmin seulement (noms français dans `StrengthNames` de l'app) ; consignes et matériel si le coach en a besoin.
public enum StrengthCatalog {
    public static let ids = [
        "squat", "lunge", "step_up", "glute_bridge", "hip_thrust", "single_leg_deadlift", "calf_raise", "wall_sit",
        "plank", "side_plank", "dead_bug", "bird_dog", "clamshell", "superman", "push_up", "mountain_climber",
    ]

    /// Catégorie et exercice Garmin de chaque identifiant, tirés de `garminconnect/exercises.py` (0.3.20).
    /// Sans équivalent exact : pont fessier → `HIP_RAISE`, chaise → squat contre le mur, bird dog → quadrupédie
    /// avec jambe levée, clamshell → jambe levée sur le côté.
    public static let garmin: [String: (category: String, name: String)] = [
        "squat": ("SQUAT", "SQUAT"),
        "lunge": ("LUNGE", "LUNGE"),
        "step_up": ("SQUAT", "STEP_UP"),
        "glute_bridge": ("HIP_RAISE", "HIP_RAISE"),
        "hip_thrust": ("HIP_RAISE", "BARBELL_HIP_THRUST_WITH_BENCH"),
        "single_leg_deadlift": ("DEADLIFT", "SINGLE_LEG_ROMANIAN_DEADLIFT_WITH_DUMBBELL"),
        "calf_raise": ("CALF_RAISE", "CALF_RAISE"),
        "wall_sit": ("SQUAT", "BODY_WEIGHT_WALL_SQUAT"),
        "plank": ("PLANK", "PLANK"),
        "side_plank": ("PLANK", "SIDE_PLANK"),
        "dead_bug": ("HIP_STABILITY", "DEAD_BUG"),
        "bird_dog": ("HIP_STABILITY", "QUADRUPED_WITH_LEG_LIFT"),
        "clamshell": ("HIP_STABILITY", "SIDE_LYING_LEG_RAISE"),
        "superman": ("HYPEREXTENSION", "SUPERMAN_FROM_FLOOR"),
        "push_up": ("PUSH_UP", "PUSH_UP"),
        "mountain_climber": ("PLANK", "MOUNTAIN_CLIMBER"),
    ]
}
