import Foundation

/// Records personnels (étape 7, n° 6) : meilleur temps sur 1, 5 et 10 km pris n'importe où dans une sortie.
public enum PersonalRecords {
    public static let distancesM: [Double] = [1000, 5000, 10000]

    /// Temps le plus court pour couvrir `distanceM` d'un seul tenant (fenêtre glissante sur le tracé), ramené à
    /// exactement `distanceM` ; nil si la sortie est plus courte. Temps écoulé : une pause compte.
    public static func bestEffortS(_ track: Track, distanceM: Double) -> Double? {
        let n = min(track.t.count, track.dist.count)
        guard n > 1, track.dist[n - 1] - track.dist[0] >= distanceM else { return nil }
        var best: Double?
        var i = 0
        for j in 1..<n {
            // Le début le plus tardif qui couvre encore la distance : la fenêtre la plus courte qui finit en j.
            while i + 1 < j, track.dist[j] - track.dist[i + 1] >= distanceM { i += 1 }
            let covered = track.dist[j] - track.dist[i]
            guard covered >= distanceM else { continue }
            let time = (track.t[j] - track.t[i]) * distanceM / covered
            if time > 0, best.map({ time < $0 }) ?? true { best = time }
        }
        return best
    }

    /// Vrai si `value` bat tous les `previous` (records : plus petit = meilleur, sauf `higherIsBetter`).
    public static func isRecord(_ value: Double?, previous: [Double], higherIsBetter: Bool = false) -> Bool {
        guard let value else { return false }
        guard let best = higherIsBetter ? previous.max() : previous.min() else { return true }
        return higherIsBetter ? value > best : value < best
    }
}
