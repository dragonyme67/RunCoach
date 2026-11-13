import Foundation
import SwiftData
import RunCoachCore

/// Coach IA côté app (F2, ARCHITECTURE.md §2.2) : résumé tiré de la base, plan jusqu'à la course, génération d'une semaine.
/// Le calcul et la validation sont dans Core (`SnapshotBuilder`, `MacroPlanner`, `CoachEngine`) ; ici, la base et le Keychain.
@MainActor
@Observable
final class CoachService {
    private let container: ModelContainer
    /// Clé IA : Keychain uniquement (CLAUDE.md).
    private let keyStore: TokenStore
    private static let keyName = "apiKey"

    private(set) var isGenerating = false
    /// Résumé de la semaine générée, ou raison du repli sur le plan de secours.
    private(set) var notice: String?

    /// Copie observable de « une clé est enregistrée » : le Keychain, lui, ne prévient pas les vues.
    private(set) var hasKey: Bool

    init(container: ModelContainer, keyStore: TokenStore = KeychainTokenStore(service: "local.runcoach.ai")) {
        self.container = container
        self.keyStore = keyStore
        self.hasKey = !(keyStore.read(Self.keyName) ?? "").isEmpty
    }

    // MARK: - Réglages

    func setKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        keyStore.write(Self.keyName, trimmed.isEmpty ? nil : trimmed)
        hasKey = !trimmed.isEmpty
    }

    /// Modèle et adresse : pas secrets, gardés dans les préférences. Défaut : Mistral (choix de l'utilisateur).
    var provider: LLMProvider {
        get {
            let defaults = UserDefaults.standard
            let url = defaults.string(forKey: "ai.baseURL").flatMap(URL.init(string:)) ?? LLMProvider.mistral.baseURL
            return LLMProvider(baseURL: url, model: defaults.string(forKey: "ai.model") ?? LLMProvider.mistral.model)
        }
        set {
            UserDefaults.standard.set(newValue.baseURL.absoluteString, forKey: "ai.baseURL")
            UserDefaults.standard.set(newValue.model, forKey: "ai.model")
        }
    }

    private func client() -> LLMClient? {
        guard let key = keyStore.read(Self.keyName), !key.isEmpty else { return nil }
        return LLMClient(http: URLSessionHTTPClient(timeoutS: 60), provider: provider, apiKey: key)
    }

    /// Un appel minuscule, sans aucune donnée personnelle : la clé et le modèle répondent-ils ?
    func testKey() async -> String {
        guard let llm = client() else { return LLMError.missingKey.userMessage }
        let schema = #"{"type":"object","additionalProperties":false,"required":["ok"],"properties":{"ok":{"type":"boolean"}}}"#
        do {
            _ = try await llm.complete(system: "Tu réponds uniquement par un objet JSON.",
                                       messages: [LLMMessage(role: "user", content: #"Réponds {"ok": true}."#)],
                                       schemaName: "ping", schema: schema)
            return "Clé valide : le coach répond."
        } catch let error as LLMError {
            return error.userMessage
        } catch {
            return LLMError.network.userMessage
        }
    }

    // MARK: - Génération

    /// Crée le plan jusqu'à la course s'il n'existe pas, puis génère la semaine qui commence lundi prochain
    /// (aujourd'hui si on est lundi). Les séances encore prévues de cette semaine sont remplacées.
    func generateNextWeek() async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        let context = container.mainContext
        guard let profile = (try? context.fetch(FetchDescriptor<AthleteProfile>()))?.first else {
            notice = "Termine d'abord la configuration."
            return
        }
        let goal = (try? context.fetch(FetchDescriptor<Goal>()))?.first { $0.isActive }
        let today = Date()
        let input = snapshotInput(profile: profile, goal: goal, context: context, today: today)
        let snapshot = SnapshotBuilder.snapshot(input)

        let monday = DayKey.weekStart(today)
        let start = DayKey.calendar.isDate(today, inSameDayAs: monday) ? monday : DayKey.addDays(7, to: monday)
        let startKey = DayKey.key(start)
        let plans = (try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []
        var activePlan = plans.first { $0.isActive && $0.macroWeeks.contains { $0.weekStart == startKey } }
        if activePlan == nil {
            let days = max(2, profile.availableWeekdays.count)
            let base = SnapshotBuilder.baseline(input, sessionsPerWeek: min(days, 3))
            let race = goal?.kind == "race" ? goal : nil
            let weeks = MacroPlanner.plan(MacroPlanner.Input(
                startWeek: start, raceDate: race?.raceDate, raceDistanceKm: race?.raceDistanceM.map { $0 / 1000 },
                v0Km: base.v0Km, l0Km: base.l0Km, availableDays: days, beginner: input.isBeginner))
            plans.forEach { $0.isActive = false }
            let created = TrainingPlan(goal: goal, macroWeeks: weeks)
            context.insert(created)
            activePlan = created
        }
        guard let plan = activePlan, let week = plan.macroWeeks.first(where: { $0.weekStart == startKey }) else {
            notice = "Ta course est passée : choisis un nouvel objectif dans Réglages."
            return
        }

        let weekKeys = (0..<7).map { DayKey.key(DayKey.addDays($0, to: start)) }
        let raceDay = goal?.raceDate.map(DayKey.key).flatMap { weekKeys.contains($0) ? $0 : nil }
        let brief = WeekBriefBuilder.brief(WeekBriefBuilder.Input(
            week: week, availableWeekdays: profile.availableWeekdays, longRunWeekday: profile.longRunWeekday,
            maxSessionMin: profile.maxSessionMinutes, wantsStrength: profile.wantsStrength, beginner: input.isBeginner,
            loadRatio: snapshot.load.ratio, lastWeekKm: snapshot.lastWeeks.last?.km ?? 0, raceDay: raceDay))

        let result = await CoachEngine.generateWeek(llm: client(), snapshot: snapshot, brief: brief,
                                                    recentPlan: recentPlan(context: context, today: today))

        let existing = (try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? []
        for workout in existing where weekKeys.contains(workout.dayKey) && workout.status == "planned" {
            context.delete(workout)
        }
        for spec in result.workouts {
            let workout = PlannedWorkout(spec: spec, source: result.source)
            context.insert(workout)
            workout.plan = plan
        }
        try? context.save()
        notice = result.notice ?? result.summary
    }

    private func snapshotInput(profile: AthleteProfile, goal: Goal?, context: ModelContext, today: Date) -> SnapshotBuilder.Input {
        let runs = ((try? context.fetch(FetchDescriptor<Run>())) ?? [])
            .filter { !$0.isStrength && $0.distanceM > 0 && $0.durationS > 0 }
            .map { RunSummary(date: $0.startDate, distanceM: $0.distanceM, durationS: $0.durationS,
                              perceivedEffort: $0.perceivedEffort, hrZoneSeconds: $0.hrZoneSeconds, avgHR: $0.avgHR) }
        let weekAgo = DayKey.key(DayKey.addDays(-7, to: today))
        let metrics = ((try? context.fetch(FetchDescriptor<DailyMetric>())) ?? [])
            .filter { $0.dayKey >= weekAgo }
            .sorted { $0.dayKey < $1.dayKey }
        let sleep = metrics.compactMap(\.sleepSeconds)
        let age = DayKey.calendar.dateComponents([.year], from: profile.birthDate, to: today).year ?? 30
        let missedSince = DayKey.key(DayKey.addDays(-14, to: today))
        let missed = ((try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? [])
            .filter { $0.status == "missed" && $0.dayKey >= missedSince }.count
        return SnapshotBuilder.Input(
            today: today, birthDate: profile.birthDate, sex: profile.sex, runningSince: profile.runningSince,
            injuryNote: profile.injuryNote, currentPain: profile.currentPain, fatigueLevel: profile.fatigueLevel,
            wantsStrength: profile.wantsStrength, strengthEquipment: profile.strengthEquipment,
            onboardingRun: RunSummary(date: today, distanceM: profile.recentRunDistanceM, durationS: profile.recentRunDurationS),
            onboardingEffort: profile.recentRunEffort, thresholdOverrideSPerKm: profile.thresholdPaceOverrideSPerKm,
            hrMaxBpm: profile.hrMax.map(Double.init) ?? HeartZones.estimatedMaxBpm(ageYears: Double(age)),
            goalKind: goal?.kind ?? "fitness", goalDistanceKm: goal?.raceDistanceM.map { $0 / 1000 },
            goalDate: goal?.raceDate, goalTargetS: goal?.targetTimeS, runs: runs,
            recovery: AthleteSnapshot.Recovery(
                sleepHAvg7d: sleep.isEmpty ? nil : ((sleep.reduce(0, +) / Double(sleep.count) / 3600) * 10).rounded() / 10,
                hrvStatus: metrics.last { $0.hrvStatus != nil }?.hrvStatus,
                restingHr: metrics.last { $0.restingHR != nil }?.restingHR),
            missedLast14d: missed)
    }

    /// Les 14 derniers jours du plan, en JSON compact : date, type, statut, km réalisés.
    private func recentPlan(context: ModelContext, today: Date) -> String {
        let since = DayKey.key(DayKey.addDays(-14, to: today))
        let todayKey = DayKey.key(today)
        let rows: [[String: Any]] = ((try? context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.dayKey)]))) ?? [])
            .filter { $0.dayKey >= since && $0.dayKey < todayKey }
            .map { w in
                var row: [String: Any] = ["date": w.dayKey, "kind": w.kind, "status": w.status]
                if let run = w.completedRun { row["km_done"] = (run.distanceM / 100).rounded() / 10 }
                return row
            }
        let data = (try? JSONSerialization.data(withJSONObject: rows)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
