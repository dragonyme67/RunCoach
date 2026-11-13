import Foundation
import SwiftData

/// Profil de l'athlète : une seule ligne. Rempli à l'onboarding, modifiable dans Réglages.
@Model
final class AthleteProfile {
    var firstName: String
    var birthDate: Date
    var sex: String?
    var heightCm: Double?
    var weightKg: Double?
    var runningSince: Date
    var recentRunDistanceM: Double
    var recentRunDurationS: Double
    /// `easy` / `moderate` / `hard`
    var recentRunEffort: String
    var thresholdPaceOverrideSPerKm: Double?
    /// 1 = lundi … 7 = dimanche
    var availableWeekdays: [Int]
    var longRunWeekday: Int
    var maxSessionMinutes: Int
    var hrMax: Int?
    var hrRest: Int?
    var injuryNote: String
    var currentPain: Bool
    /// `mild` (gêne légère) ou `severe` (douleur nette) quand `currentPain` est vrai. Optionnel : ajouté après l'étape 2.
    var painLevel: String?
    /// `low` / `normal` / `high`
    var fatigueLevel: String
    var wantsStrength: Bool
    /// `none` / `dumbbells` / `gym`
    var strengthEquipment: String
    var medicalDisclaimerAcceptedAt: Date?
    var updatedAt: Date

    init(firstName: String = "",
         birthDate: Date = Date(),
         runningSince: Date = Date(),
         recentRunDistanceM: Double = 5000,
         recentRunDurationS: Double = 1950,
         recentRunEffort: String = "moderate",
         availableWeekdays: [Int] = [2, 4, 7],
         longRunWeekday: Int = 7,
         maxSessionMinutes: Int = 60) {
        self.firstName = firstName
        self.birthDate = birthDate
        self.runningSince = runningSince
        self.recentRunDistanceM = recentRunDistanceM
        self.recentRunDurationS = recentRunDurationS
        self.recentRunEffort = recentRunEffort
        self.availableWeekdays = availableWeekdays
        self.longRunWeekday = longRunWeekday
        self.maxSessionMinutes = maxSessionMinutes
        self.injuryNote = ""
        self.currentPain = false
        self.fatigueLevel = "normal"
        self.wantsStrength = true
        self.strengthEquipment = "none"
        self.updatedAt = Date()
    }

    /// `none`, `mild` ou `severe`. Une douleur enregistrée sans niveau (ancienne version) compte comme nette.
    var pain: String {
        get { currentPain ? (painLevel == "mild" ? "mild" : "severe") : "none" }
        set {
            currentPain = newValue != "none"
            painLevel = newValue == "none" ? nil : newValue
            updatedAt = Date()
        }
    }
}
