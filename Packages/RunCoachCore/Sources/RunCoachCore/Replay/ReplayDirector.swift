import Foundation

/// Caméra de la carte : point visé, distance de l'œil, inclinaison (0 = vue du dessus), cap.
public struct ReplayCamera: Equatable, Sendable {
    public var centerLat: Double
    public var centerLon: Double
    public var distanceM: Double
    public var pitchDeg: Double
    public var headingDeg: Double

    public init(centerLat: Double, centerLon: Double, distanceM: Double, pitchDeg: Double, headingDeg: Double) {
        self.centerLat = centerLat
        self.centerLon = centerLon
        self.distanceM = distanceM
        self.pitchDeg = pitchDeg
        self.headingDeg = headingDeg
    }
}

/// Règles de la caméra et de la lecture du replay (ARCHITECTURE.md §8, étapes 3.1 et 3.2). Pures et testées.
public enum ReplayDirector {
    /// Entrée : vue d'ensemble immobile, puis descente vers le coureur. Sortie : remontée.
    public static let introHoldS = 0.8
    public static let introDescentS = 2.5
    public static let outroS = 2.5

    /// Vue d'ensemble du tracé entier, du dessus, nord en haut. `viewAspect` = largeur / hauteur de la carte.
    // shortcut: distance tirée d'un champ de vision supposé (≈ 30°) et d'une marge pour le bandeau du bas ;
    // à recaler si la vue d'ensemble coupe le tracé ou le montre trop petit sur l'iPhone.
    public static func overview(of track: Track, viewAspect: Double) -> ReplayCamera {
        guard let minLat = track.lat.min(), let maxLat = track.lat.max(),
              let minLon = track.lon.min(), let maxLon = track.lon.max() else {
            return ReplayCamera(centerLat: 0, centerLon: 0, distanceM: 2000, pitchDeg: 0, headingDeg: 0)
        }
        let centerLat = (minLat + maxLat) / 2
        let spanNorthM = (maxLat - minLat) * 111_320
        let spanEastM = (maxLon - minLon) * 111_320 * cos(centerLat * .pi / 180)
        let spanM = max(spanNorthM, spanEastM / max(0.1, viewAspect))
        return ReplayCamera(centerLat: centerLat, centerLon: (minLon + maxLon) / 2,
                            distanceM: max(800, spanM * 2.6), pitchDeg: 0, headingDeg: 0)
    }

    /// Passage progressif de `a` à `b` (`t` de 0 à 1, accéléré puis freiné). Zoom géométrique : la descente
    /// paraît régulière à toutes les hauteurs. Cap par le plus court chemin.
    public static func blend(_ a: ReplayCamera, _ b: ReplayCamera, t: Double) -> ReplayCamera {
        let x = max(0, min(1, t))
        let e = x * x * (3 - 2 * x)
        let turn = (b.headingDeg - a.headingDeg + 540).truncatingRemainder(dividingBy: 360) - 180
        return ReplayCamera(
            centerLat: a.centerLat + (b.centerLat - a.centerLat) * e,
            centerLon: a.centerLon + (b.centerLon - a.centerLon) * e,
            distanceM: a.distanceM * pow(b.distanceM / a.distanceM, e),
            pitchDeg: a.pitchDeg + (b.pitchDeg - a.pitchDeg) * e,
            headingDeg: (a.headingDeg + turn * e + 360).truncatingRemainder(dividingBy: 360))
    }

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
