import Foundation

extension Track {
    /// Tracé construit à partir des détails Garmin. Colonnes repérées par leur `key`, jamais par leur position.
    /// Relevé sans latitude ou longitude : supprimé. Valeur manquante : dernière valeur connue (ou la suivante en tête).
    /// `nil` sans GPS (tapis, renfo) ou sans temps ni distance.
    public init?(details: ActivityDetailsDTO) {
        guard let descriptors = details.metricDescriptors, let rows = details.activityDetailMetrics else { return nil }
        var indexByKey: [String: Int] = [:]
        for d in descriptors {
            if let key = d.key, let index = d.metricsIndex { indexByKey[key] = index }
        }
        func column(_ keys: String...) -> [Double?]? {
            guard let index = keys.lazy.compactMap({ indexByKey[$0] }).first else { return nil }
            return rows.map { row in
                guard let metrics = row.metrics, metrics.indices.contains(index) else { return nil }
                return metrics[index]
            }
        }
        guard let latColumn = column("directLatitude"), let lonColumn = column("directLongitude") else { return nil }
        let kept = rows.indices.filter { i in
            guard let la = latColumn[i], let lo = lonColumn[i] else { return false }
            return !(la == 0 && lo == 0)
        }
        guard kept.count >= 2 else { return nil }
        func filled(_ c: [Double?]?) -> [Double]? { c.flatMap { c in Track.fill(kept.map { c[$0] }) } }

        var time = filled(column("sumElapsedDuration", "sumDuration"))
        if time == nil, let stamps = filled(column("directTimestamp")) {
            time = stamps.map { ($0 - stamps[0]) / 1000 }
        }
        guard let time, let dist = filled(column("sumDistance")) else { return nil }
        // `directDoubleCadence` = pas par minute des deux pieds, l'unité de l'app. `directRunCadence` = un pied.
        let cadence = filled(column("directDoubleCadence")) ?? filled(column("directRunCadence"))?.map { $0 * 2 }

        self.init(t: time, lat: kept.map { latColumn[$0]! }, lon: kept.map { lonColumn[$0]! }, dist: dist,
                  ele: filled(column("directElevation")), hr: filled(column("directHeartRate")),
                  cad: cadence, speed: filled(column("directSpeed")))
    }

    static func fill(_ values: [Double?]) -> [Double]? {
        guard let first = values.lazy.compactMap({ $0 }).first else { return nil }
        var last = first
        return values.map { value in
            if let value { last = value }
            return last
        }
    }
}
