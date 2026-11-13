import Foundation

/// Zones de fréquence cardiaque par défaut (ARCHITECTURE.md §6.3) : 50, 60, 70, 80, 90, 100 % de la FC max.
public enum HeartZones {
    /// FC max estimée : 208 − 0,7 × âge.
    public static func estimatedMaxBpm(ageYears: Double) -> Double {
        208 - 0.7 * ageYears
    }

    /// Zone de 1 à 5 ; sous 60 % de la FC max, zone 1 ; au-delà du maximum, zone 5.
    public static func zone(bpm: Double, maxBpm: Double) -> Int {
        guard maxBpm > 0 else { return 1 }
        return min(5, max(1, Int(bpm * 10 / maxBpm) - 4))
    }
}
