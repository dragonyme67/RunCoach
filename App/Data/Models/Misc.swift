import Foundation
import SwiftData

/// Métriques quotidiennes Garmin (sommeil, HRV, VO2max…). Toutes optionnelles.
@Model
final class DailyMetric {
    @Attribute(.unique) var dayKey: String
    var sleepSeconds: Double?
    var sleepScore: Int?
    var hrvLastNightMs: Double?
    var hrvStatus: String?
    var restingHR: Int?
    var vo2max: Double?
    var trainingReadiness: Int?
    var trainingStatus: String?
    var bodyBattery: Int?

    init(dayKey: String) {
        self.dayKey = dayKey
    }
}

@Model
final class ChatMessage {
    var uuid: UUID
    /// `user` / `assistant`
    var role: String
    var text: String
    var createdAt: Date
    /// `[PlanAction]` en JSON (étape 4).
    var actionsData: Data?
    /// Résumé lisible des actions proposées, une ligne par action.
    var actionLines: [String]
    /// `none` / `proposed` / `applied` / `rejected`
    var actionsState: String

    init(role: String, text: String, createdAt: Date = Date(), actionLines: [String] = [], actionsState: String = "none") {
        self.uuid = UUID()
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.actionLines = actionLines
        self.actionsState = actionsState
    }
}

/// État de la synchro Garmin : une seule ligne.
@Model
final class SyncState {
    var lastGarminSyncAt: Date?
    var lastSyncError: String?
    var backfillDone: Bool
    var garminDisplayName: String?
    var nextAllowedGarminCallAt: Date?
    var consecutiveFailures: Int

    init() {
        self.backfillDone = false
        self.consecutiveFailures = 0
    }
}
