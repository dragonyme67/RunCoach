import Foundation

/// Catalogue fixe des exercices de renforcement (ARCHITECTURE.md §5.3.1).
/// shortcut: identifiants seulement (noms français dans `StrengthNames` de l'app), consignes, matériel et catégorie Garmin à l'étape 5.
public enum StrengthCatalog {
    public static let ids = [
        "squat", "lunge", "step_up", "glute_bridge", "hip_thrust", "single_leg_deadlift", "calf_raise", "wall_sit",
        "plank", "side_plank", "dead_bug", "bird_dog", "clamshell", "superman", "push_up", "mountain_climber",
    ]
}
