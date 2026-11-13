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

    /// Découpage par kilomètre, le dernier partiel gardé s'il dépasse 50 m.
    /// Calculé depuis le tracé : les « tours » Garmin suivent les étapes d'une séance, pas les kilomètres.
    public func kmSplits() -> [KmSplit] {
        let n = min(t.count, dist.count)
        guard n > 1 else { return [] }
        var splits: [KmSplit] = []
        var startIndex = 0
        var startTime = t[0]
        var nextKm = 1.0

        func close(at index: Int, time: Double, distanceM: Double) {
            let range = startIndex...index
            func mean(_ c: [Double]?) -> Double? { c.map { c in range.map { c[$0] }.reduce(0, +) / Double(range.count) } }
            var gain: Double?, loss: Double?
            if let ele {
                gain = 0; loss = 0
                for i in range.dropFirst() {
                    let delta = ele[i] - ele[i - 1]
                    if delta > 0 { gain! += delta } else { loss! -= delta }
                }
            }
            splits.append(KmSplit(index: splits.count + 1, distanceM: distanceM, durationS: time - startTime,
                                  avgHR: mean(hr).map { Int($0.rounded()) }, avgCadenceSpm: mean(cad),
                                  elevationGainM: gain, elevationLossM: loss))
            startIndex = index
            startTime = time
        }

        for i in 1..<n {
            while dist[i] - dist[0] >= nextKm * 1000 {
                let target = dist[0] + nextKm * 1000
                let f = (target - dist[i - 1]) / (dist[i] - dist[i - 1])
                close(at: i, time: t[i - 1] + f * (t[i] - t[i - 1]), distanceM: 1000)
                nextKm += 1
            }
        }
        let rest = dist[n - 1] - dist[0] - (nextKm - 1) * 1000
        if rest > 50 {
            close(at: n - 1, time: t[n - 1], distanceM: rest)
        }
        return splits
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

/// Un kilomètre de sortie (ou le dernier morceau), prêt à copier dans l'entité `Split`.
public struct KmSplit: Equatable, Sendable {
    /// À partir de 1.
    public var index: Int
    public var distanceM: Double
    public var durationS: Double
    public var avgHR: Int?
    public var avgCadenceSpm: Double?
    public var elevationGainM: Double?
    public var elevationLossM: Double?

    public var avgSpeedMps: Double? { durationS > 0 ? distanceM / durationS : nil }
}
