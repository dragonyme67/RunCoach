import Foundation
import BackgroundTasks

/// Synchro en arrière-plan (`BGAppRefreshTask`). iOS décide quand elle tourne, et ne la lance jamais
/// si l'app a été fermée d'un balayage : la synchro fiable reste celle de l'ouverture de l'app.
enum BackgroundSync {
    /// Doit figurer dans `BGTaskSchedulerPermittedIdentifiers` (project.yml).
    static let identifier = "local.runcoach.app.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
