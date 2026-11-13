import Foundation

/// Règles de la caméra et de la lecture du replay (ARCHITECTURE.md §8, étape 3.1). Pures et testées.
public enum ReplayDirector {
    /// Distance (m) du point visé devant le coureur : la caméra s'oriente vers lui.
    public static let lookAheadM = 80.0

    /// Durée de lecture à ×1 : la sortie entière en 60 à 90 s.
    /// La lecture avance à vitesse constante sur la distance : marche et arrêts ne la ralentissent pas
    /// (demande de l'utilisateur, 2026-11-13).
    public static func playbackDurationS(runDurationS: Double) -> Double {
        min(90, max(60, runDurationS / 30))
    }

    /// Cap de la caméra rapproché du cap visé par le plus court chemin angulaire (de 350° à 10° via 0°),
    /// avec un lissage exponentiel : la carte accompagne un virage avec un léger retard au lieu de sursauter.
    public static func smoothHeading(_ current: Double, toward target: Double, dt: Double, timeConstantS: Double = 0.6) -> Double {
        let delta = (target - current + 540).truncatingRemainder(dividingBy: 360) - 180
        let k = 1 - exp(-max(0, dt) / timeConstantS)
        return (current + delta * k + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Vrai si un point du sol est devant la caméra (profondeur positive), qui regarde `center` depuis
    /// `cameraDistanceM` mètres avec l'inclinaison `pitchDeg` (0 = vue du dessus) et le cap `headingDeg`.
    /// Un point derrière la caméra est projeté n'importe où sur l'écran : il faut l'écarter du trait.
    public static func isInFrontOfCamera(lat: Double, lon: Double, centerLat: Double, centerLon: Double,
                                         headingDeg: Double, cameraDistanceM: Double, pitchDeg: Double) -> Bool {
        let metersPerDegree = 111_320.0
        let east = (lon - centerLon) * metersPerDegree * cos(centerLat * .pi / 180)
        let north = (lat - centerLat) * metersPerDegree
        let heading = headingDeg * .pi / 180
        let forward = east * sin(heading) + north * cos(heading)
        // Profondeur le long de l'axe de visée ; marge de 20 % pour rester loin du plan de la caméra.
        let depth = forward * sin(pitchDeg * .pi / 180) + cameraDistanceM
        return depth > 0.2 * cameraDistanceM
    }
}
