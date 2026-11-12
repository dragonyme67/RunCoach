import Foundation
import SwiftData

@Model
final class Goal {
    var uuid: UUID
    /// `race` / `fitness`
    var kind: String
    var name: String
    var raceDistanceM: Double?
    var raceDate: Date?
    var targetTimeS: Double?
    var isActive: Bool

    init(kind: String = "race", name: String, raceDistanceM: Double? = nil, raceDate: Date? = nil,
         targetTimeS: Double? = nil, isActive: Bool = true) {
        self.uuid = UUID()
        self.kind = kind
        self.name = name
        self.raceDistanceM = raceDistanceM
        self.raceDate = raceDate
        self.targetTimeS = targetTimeS
        self.isActive = isActive
    }
}
