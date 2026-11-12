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
