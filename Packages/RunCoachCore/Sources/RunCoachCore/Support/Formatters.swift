import Foundation

/// Mise en forme des grandeurs de course, en français.
public enum Fmt {
    /// « 6:30 » pour 390 s/km.
    public static func pace(sPerKm: Double) -> String {
        guard sPerKm.isFinite, sPerKm > 0 else { return "–" }
        let total = Int(sPerKm.rounded())
        return "\(total / 60):" + twoDigits(total % 60)
    }

    public static func pace(speedMps: Double) -> String {
        guard speedMps.isFinite, speedMps > 0.1 else { return "–" }
        return pace(sPerKm: 1000 / speedMps)
    }

    /// « 35:12 » ou « 1:05:12 ».
    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h):" + twoDigits(m) + ":" + twoDigits(s) }
        return "\(m):" + twoDigits(s)
    }

    /// « 45 s », « 35 min », « 1 h 05 ».
    public static func minutes(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–" }
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let m = Int((Double(total) / 60).rounded())
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h " + twoDigits(m % 60)
    }

    /// « 5,02 » pour 5 020 m.
    public static func km(_ meters: Double, decimals: Int = 2) -> String {
        guard meters.isFinite else { return "–" }
        return decimal(meters / 1000, decimals: decimals)
    }

    public static func decimal(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func twoDigits(_ n: Int) -> String {
        n < 10 ? "0\(n)" : "\(n)"
    }
}
