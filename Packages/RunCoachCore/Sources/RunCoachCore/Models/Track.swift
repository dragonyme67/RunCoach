import Foundation

/// Tracé d'une sortie, en colonnes. Tous les tableaux présents ont la même longueur.
public struct Track: Codable, Equatable, Sendable {
    /// Secondes depuis le départ.
    public var t: [Double]
    public var lat: [Double]
    public var lon: [Double]
    /// Mètres cumulés.
    public var dist: [Double]
    /// Mètres.
    public var ele: [Double]?
    /// Battements par minute.
    public var hr: [Double]?
    /// Pas par minute.
    public var cad: [Double]?
    /// Mètres par seconde.
    public var speed: [Double]?

    public init(t: [Double], lat: [Double], lon: [Double], dist: [Double],
                ele: [Double]? = nil, hr: [Double]? = nil, cad: [Double]? = nil, speed: [Double]? = nil) {
        self.t = t
        self.lat = lat
        self.lon = lon
        self.dist = dist
        self.ele = ele
        self.hr = hr
        self.cad = cad
        self.speed = speed
    }

    public var count: Int { t.count }

    /// Cap de la course au point `index`, en degrés (0 = nord, 90 = est),
    /// lissé sur `span` points de part et d'autre pour que la carte ne tremble pas.
    public func heading(at index: Int, span: Int = 6) -> Double {
        let n = min(lat.count, lon.count)
        guard n > 1 else { return 0 }
        let i = max(0, min(n - 1, index))
        let a = max(0, i - span)
        let b = min(n - 1, i + span)
        let lat1 = lat[a] * .pi / 180
        let lat2 = lat[b] * .pi / 180
        let dLon = (lon[b] - lon[a]) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Position et cap à la fraction `progress` (0 à 1) du tracé, interpolés entre deux relevés :
    /// le replay glisse au lieu de sauter d'un point au suivant.
    public func pose(at progress: Double) -> (lat: Double, lon: Double, heading: Double) {
        let n = min(lat.count, lon.count)
        guard n > 1 else { return (lat.first ?? 0, lon.first ?? 0, 0) }
        let position = max(0, min(1, progress)) * Double(n - 1)
        let i = min(n - 2, Int(position))
        let f = position - Double(i)
        // Plus court chemin angulaire : de 350° à 10° on passe par 0°, pas par 180°.
        let from = heading(at: i)
        let turn = (heading(at: i + 1) - from + 540).truncatingRemainder(dividingBy: 360) - 180
        return (
            lat[i] + (lat[i + 1] - lat[i]) * f,
            lon[i] + (lon[i + 1] - lon[i]) * f,
            (from + turn * f + 360).truncatingRemainder(dividingBy: 360)
        )
    }

    /// Vrai si toutes les colonnes présentes ont la même longueur.
    public var isConsistent: Bool {
        let n = t.count
        guard lat.count == n, lon.count == n, dist.count == n else { return false }
        let optionalColumns: [[Double]?] = [ele, hr, cad, speed]
        for column in optionalColumns {
            if let column = column, column.count != n { return false }
        }
        return true
    }
}
