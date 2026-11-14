import Foundation
import SwiftData
import RunCoachCore

/// Synchro Garmin (flux F1, ARCHITECTURE.md §2.2, §4.3).
/// Premier passage : tout l'historique (liste complète, puis le tracé de chaque sortie GPS, puis 28 jours de
/// sommeil et de récupération). Passages suivants : seulement ce qui manque.
/// Chaque activité est enregistrée dès qu'elle est lue : un import interrompu reprend où il s'est arrêté.
@MainActor
@Observable
final class SyncEngine {
    enum Phase: Equatable {
        case idle, syncing, offline, needsLogin
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Avancement lisible pendant la synchro (« Tracés : 12 / 140 »).
    private(set) var progress: String?
    /// Journal en mémoire pour Réglages → Garmin → Diagnostic. Jamais de ticket, de jeton ni de paramètre de requête.
    private(set) var diagnostics: [String] = []
    private(set) var isConnected: Bool

    private let context: ModelContext
    private let auth: GarminAuth
    private let api: GarminAPI
    @ObservationIgnored private var running = false

    init(container: ModelContainer, store: TokenStore, http: HTTPClient) {
        context = container.mainContext
        auth = GarminAuth(http: http, store: store)
        api = GarminAPI(auth: auth, http: http)
        isConnected = auth.hasSession
    }

    /// Message à afficher, ou `nil` si tout va bien.
    var message: String? {
        switch phase {
        case .needsLogin: return "Reconnecte-toi à Garmin."
        case .offline: return "Hors ligne : nouvel essai à la prochaine ouverture."
        case .failed(let text): return text
        case .idle, .syncing: return nil
        }
    }

    func log(_ line: String) {
        diagnostics.append(Date().formatted(date: .omitted, time: .standard) + "  " + line)
        if diagnostics.count > 300 { diagnostics.removeFirst(diagnostics.count - 300) }
    }

    /// Appelé une seule fois par ticket capté. Aucune nouvelle tentative automatique en cas d'échec.
    func login(ticket: String) async {
        log("Échange du ticket contre les jetons")
        do {
            try await auth.exchange(ticket: ticket)
            isConnected = true
            phase = .idle
            log("Connecté à Garmin")
            await sync(background: false)
        } catch {
            fail(error)
        }
    }

    func logout() async {
        await auth.logout()
        isConnected = false
        syncState.garminDisplayName = nil
        phase = .idle
        save()
        log("Déconnecté")
    }

    /// À l'ouverture de l'app : seulement si la dernière synchro date de plus de 15 min.
    func syncIfStale() async {
        if let last = syncState.lastGarminSyncAt, Date().timeIntervalSince(last) < SyncPolicy.staleAfterS { return }
        await sync(background: false)
    }

    @discardableResult
    func sync(background: Bool) async -> Bool {
        guard isConnected, !running else { return false }
        let state = syncState
        if let until = state.nextAllowedGarminCallAt, until > Date() {
            phase = .failed(Self.waitMessage(until))
            return false
        }
        running = true
        phase = .syncing
        defer {
            running = false
            progress = nil
            save()
        }
        let start = await api.requestCount
        let budget = SyncPolicy.budget(background: background, backfillDone: state.backfillDone)
        let hasBudget: () async -> Bool = { [api] in await api.requestCount - start < budget }
        log(background ? "Synchro en arrière-plan" : "Synchro")

        do {
            if state.garminDisplayName == nil {
                let profile = try await api.socialProfile()
                state.garminDisplayName = profile.fullName ?? profile.displayName
            }
            let listComplete = try await importList(untilKnown: state.backfillDone, hasBudget: hasBudget)
            // Avant les tracés : pendant le premier import, ceux-ci peuvent prendre de longues minutes.
            try await mirrorWatch(hasBudget: hasBudget)
            let detailsComplete = try await importDetails(hasBudget: hasBudget)
            try await importMetrics(hasBudget: hasBudget)

            state.lastGarminSyncAt = Date()
            state.lastSyncError = nil
            state.consecutiveFailures = 0
            state.nextAllowedGarminCallAt = nil
            state.backfillDone = listComplete && detailsComplete
            phase = .idle
            let used = await api.requestCount - start
            log("Synchro terminée : \(used) requêtes")
            return true
        } catch {
            fail(error)
            return false
        }
    }

    /// Envoi sur la montre seul, sans import (F3) : après une génération, des actions du chat ou une séance annulée.
    // shortcut: ignoré si une synchro tourne déjà ; elle envoie déjà, sauf un changement fait pendant son envoi (repris au passage suivant).
    /// `retryFailed` (bouton « Envoyer sur la montre ») : les séances en échec retrouvent leurs 3 essais.
    func pushWorkouts(retryFailed: Bool = false) async {
        guard isConnected, !running else { return }
        if let until = syncState.nextAllowedGarminCallAt, until > Date() {
            phase = .failed(Self.waitMessage(until))
            return
        }
        if retryFailed {
            for workout in (try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? [] where workout.garminSyncState == "failed" {
                workout.garminAttempts = nil
            }
        }
        running = true
        phase = .syncing
        defer {
            running = false
            progress = nil
            save()
        }
        let start = await api.requestCount
        let budget = SyncPolicy.budget(background: false, backfillDone: true)
        do {
            try await mirrorWatch(hasBudget: { [api] in await api.requestCount - start < budget })
            phase = .idle
        } catch {
            fail(error)
        }
    }

    // MARK: - Étapes

    /// Le calendrier Garmin devient le miroir des séances prévues des 7 prochains jours (`WatchSync`) :
    /// suppression des workouts « RC · » en trop, puis création et planification de ce qui manque.
    /// Une séance refusée par Garmin (400…) passe en `failed` sans bloquer les autres ; 3 essais au plus.
    private func mirrorWatch(hasBudget: () async -> Bool) async throws {
        guard await hasBudget() else { return }
        progress = "Séances de la montre…"
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>())
        let remote: [WorkoutRefDTO]
        do { remote = try await api.workouts() } catch {
            guard Self.concernsOneItem(error) else { throw error }
            log("Liste des séances Garmin refusée (\(Self.describe(error))) : envoi reporté")
            return
        }
        let decision = WatchSync.decide(
            local: workouts.map {
                WatchSync.Local(dayKey: $0.dayKey, status: $0.status, garminWorkoutId: $0.garminWorkoutId,
                                state: $0.garminSyncState, attempts: $0.garminAttempts ?? 0)
            },
            remote: remote, today: Date())
        // Identifiants oubliés d'abord : un workout pas encore supprimé le sera au passage suivant (toujours en trop).
        for index in decision.forget {
            let workout = workouts[index]
            workout.garminWorkoutId = nil
            workout.garminScheduleId = nil
            if workout.status == "planned" { workout.garminSyncState = "notSent" }
        }
        save()
        var deleted = 0
        for id in decision.delete {
            guard await hasBudget() else { return }
            do {
                try await api.deleteWorkout(id)
                deleted += 1
            } catch {
                guard Self.concernsOneItem(error) else { throw error }
                log("Suppression d'une séance refusée (\(Self.describe(error)))")
            }
        }
        var sent = 0
        for index in decision.send {
            guard await hasBudget() else { break }
            let workout = workouts[index]
            guard let spec = workout.spec else { continue }
            do {
                let id = try await api.createWorkout(GarminWorkoutMapper.body(spec))
                // Gardé tout de suite : si la planification échoue, le workout sera supprimé au passage suivant.
                workout.garminWorkoutId = id
                save()
                workout.garminScheduleId = try await api.schedule(workoutId: id, day: workout.dayKey)
                workout.garminSyncState = "sent"
                workout.garminSyncError = nil
                workout.garminAttempts = nil
                sent += 1
            } catch {
                guard Self.concernsOneItem(error) else { throw error }
                workout.garminAttempts = (workout.garminAttempts ?? 0) + 1
                workout.garminSyncState = "failed"
                workout.garminSyncError = "Garmin a refusé la séance (\(Self.describe(error)))."
                log("Séance du \(workout.dayKey) refusée (\(Self.describe(error)))")
            }
            save()
        }
        if deleted + sent > 0 { log("Montre : \(sent) séances envoyées, \(deleted) supprimées") }
    }

    /// Liste des activités, de la plus récente à la plus ancienne. Avant la fin du premier import : jusqu'au bout
    /// de l'historique. Ensuite : jusqu'à la première page qui contient une activité déjà en base.
    /// Renvoie vrai si la liste a été parcourue jusqu'où il fallait.
    private func importList(untilKnown: Bool, hasBudget: () async -> Bool) async throws -> Bool {
        var known = Set(try context.fetch(FetchDescriptor<Run>()).map(\.garminActivityId))
        var start = 0
        while await hasBudget() {
            progress = "Liste des activités…"
            let page = try await api.activities(start: start, limit: SyncPolicy.pageSize)
            var sawKnown = false
            var added = 0
            for dto in page {
                guard let activity = ImportedActivity(dto) else { continue }
                if known.contains(activity.garminActivityId) {
                    sawKnown = true
                } else {
                    context.insert(Run(imported: activity))
                    known.insert(activity.garminActivityId)
                    added += 1
                }
            }
            save()
            log("Liste à partir de \(start) : \(page.count) activités, \(added) nouvelles")
            if page.count < SyncPolicy.pageSize || (untilKnown && sawKnown) { return true }
            start += SyncPolicy.pageSize
        }
        return false
    }

    /// Tracé et kilomètres de chaque activité GPS pas encore complète, de la plus récente à la plus ancienne.
    /// Renvoie vrai s'il ne reste rien à télécharger.
    private func importDetails(hasBudget: () async -> Bool) async throws -> Bool {
        let pending = try context.fetch(FetchDescriptor<Run>(
            predicate: #Predicate { $0.detailState == "summaryOnly" },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]))
        for (index, run) in pending.enumerated() {
            guard await hasBudget() else { return false }
            progress = "Tracés : \(index + 1) / \(pending.count)"
            do {
                run.applyDetails(Track(details: try await api.details(activityId: run.garminActivityId)))
            } catch {
                // Une réponse illisible ou une erreur propre à cette activité ne bloque pas les autres.
                guard Self.concernsOneItem(error) else { throw error }
                run.detailAttempts += 1
                if run.detailAttempts >= SyncPolicy.maxDetailAttempts { run.detailState = "failed" }
                log("Détails refusés pour une activité (\(Self.describe(error)))")
            }
            save()
        }
        return true
    }

    /// Statut d'entraînement et VO2max (une requête), puis sommeil et FC de repos des jours manquants.
    private func importMetrics(hasBudget: () async -> Bool) async throws {
        guard await hasBudget() else { return }
        progress = "Sommeil et récupération…"
        let today = Date()
        var status: TrainingStatusDTO?
        do { status = try await api.trainingStatus(day: DayKey.key(today)) } catch {
            guard Self.concernsOneItem(error) else { throw error }
        }
        let existing = try context.fetch(FetchDescriptor<DailyMetric>())
        let byDay = Dictionary(existing.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
        for (index, day) in SyncPolicy.metricDays(today: today, existing: Set(byDay.keys)).enumerated() {
            guard await hasBudget() else { return }
            let sleep: SleepDTO
            do { sleep = try await api.sleep(day: day) } catch {
                guard Self.concernsOneItem(error) else { throw error }
                continue
            }
            let metric: DailyMetric
            if let found = byDay[day] {
                metric = found
            } else {
                metric = DailyMetric(dayKey: day)
                context.insert(metric)
            }
            metric.apply(ImportedDailyMetric(dayKey: day, sleep: sleep, status: index == 0 ? status : nil))
        }
        save()
    }

    // MARK: - Erreurs

    private func fail(_ error: Error) {
        let state = syncState
        if error is CancellationError {
            phase = .idle
            log("Synchro interrompue par iOS")
            return
        }
        let garminError = error as? GarminError
        switch garminError {
        case .needsLogin?:
            isConnected = auth.hasSession
            phase = .needsLogin
        case .rateLimited?, .blocked?:
            let until = SyncPolicy.nextAllowedCall(after: garminError!, failures: state.consecutiveFailures, now: Date())
            state.nextAllowedGarminCallAt = until
            state.consecutiveFailures += 1
            phase = .failed(Self.waitMessage(until ?? Date()))
        case .network?:
            phase = .offline
        default:
            state.consecutiveFailures += 1
            phase = .failed("La synchro Garmin a échoué (\(Self.describe(error))). Nouvel essai à la prochaine ouverture.")
        }
        state.lastSyncError = Self.describe(error)
        log("Arrêt : \(Self.describe(error))")
        save()
    }

    private static func concernsOneItem(_ error: Error) -> Bool {
        switch error as? GarminError {
        case .decoding?, .http?: return true
        default: return false
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error as? GarminError {
        case .needsLogin?: return "session expirée"
        case .rateLimited?: return "trop de requêtes (429)"
        case .blocked?: return "accès refusé (403)"
        case .network?: return "réseau"
        case .decoding?: return "réponse illisible"
        case .http(let code)?: return "HTTP \(code)"
        case nil: return "erreur inattendue"
        }
    }

    private static func waitMessage(_ until: Date) -> String {
        "Garmin refuse la connexion pour le moment. Nouvel essai automatique après "
            + until.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(Locale(identifier: "fr_FR"))) + "."
    }

    // MARK: - Base

    private var syncState: SyncState {
        if let state = try? context.fetch(FetchDescriptor<SyncState>()).first { return state }
        let state = SyncState()
        context.insert(state)
        return state
    }

    private func save() {
        do { try context.save() } catch { log("Enregistrement local impossible") }
    }
}
