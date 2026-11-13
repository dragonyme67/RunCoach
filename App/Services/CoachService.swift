import Foundation
import SwiftData
import RunCoachCore

/// Coach IA côté app (F2, ARCHITECTURE.md §2.2) : résumé tiré de la base, plan jusqu'à la course, génération d'une semaine.
/// Le calcul et la validation sont dans Core (`SnapshotBuilder`, `MacroPlanner`, `CoachEngine`) ; ici, la base et le Keychain.
@MainActor
@Observable
final class CoachService {
    private let container: ModelContainer
    /// Clés IA : Keychain uniquement (CLAUDE.md), une par fournisseur.
    private let keyStore: TokenStore

    private(set) var isGenerating = false
    /// Résumé de la semaine générée, ou raison du repli sur le plan de secours.
    private(set) var notice: String?
    private(set) var isReplying = false
    /// Erreur du dernier message du chat (non enregistrée).
    private(set) var chatError: String?

    /// Fournisseur choisi dans Réglages (Groq par défaut). Pas secret : gardé dans les préférences.
    var providerId: String {
        didSet {
            UserDefaults.standard.set(providerId, forKey: "ai.provider")
            refreshHasKey()
        }
    }
    /// Copie observable de « une clé est enregistrée pour ce fournisseur » : le Keychain ne prévient pas les vues.
    private(set) var hasKey = false

    init(container: ModelContainer, keyStore: TokenStore = KeychainTokenStore(service: "local.runcoach.ai")) {
        self.container = container
        self.keyStore = keyStore
        let saved = UserDefaults.standard.string(forKey: "ai.provider")
        self.providerId = LLMProvider.presets.contains { $0.id == saved } ? saved! : LLMProvider.groq.id
        refreshHasKey()
    }

    // MARK: - Réglages

    private var keyName: String { "apiKey." + providerId }

    private func refreshHasKey() {
        hasKey = !(keyStore.read(keyName) ?? "").isEmpty
    }

    func setKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        keyStore.write(keyName, trimmed.isEmpty ? nil : trimmed)
        clients[providerId] = nil
        refreshHasKey()
    }

    var provider: LLMProvider {
        LLMProvider.presets.first { $0.id == providerId } ?? .groq
    }

    /// Journal des appels à l'IA depuis l'ouverture de l'app (Réglages → Coach IA → Diagnostic) :
    /// modèle, code HTTP, durée, message d'erreur du fournisseur. Jamais le contenu envoyé.
    private(set) var diagnostics: [String] = []
    /// Un client par fournisseur et par clé : il retient les modèles épuisés pendant la session.
    /// (Le service vit autant que l'app : la référence circulaire via le journal est sans conséquence.)
    @ObservationIgnored private var clients: [String: (key: String, client: LLMClient)] = [:]

    private func client() -> LLMClient? {
        guard let key = keyStore.read(keyName), !key.isEmpty else { return nil }
        if let cached = clients[providerId], cached.key == key { return cached.client }
        let name = provider.name
        let client = LLMClient(http: URLSessionHTTPClient(timeoutS: 60), provider: provider, apiKey: key) { line in
            let stamp = Date().formatted(date: .omitted, time: .standard)
            Task { @MainActor in self.addDiagnostic("\(stamp) · \(name) · \(line)") }
        }
        clients[providerId] = (key, client)
        return client
    }

    private func addDiagnostic(_ line: String) {
        diagnostics.append(line)
        if diagnostics.count > 100 { diagnostics.removeFirst(diagnostics.count - 100) }
    }

    /// Un appel minuscule à chaque modèle, sans aucune donnée personnelle : lesquels répondent avec cette clé ?
    func testModels() async -> [String] {
        guard let llm = client() else { return [LLMError.missingKey.userMessage] }
        let schema = #"{"type":"object","additionalProperties":false,"required":["ok"],"properties":{"ok":{"type":"boolean"}}}"#
        var lines: [String] = []
        for model in provider.models {
            do {
                _ = try await llm.complete(system: "Tu réponds uniquement par un objet JSON.",
                                           messages: [LLMMessage(role: "user", content: #"Réponds {"ok": true}."#)],
                                           schemaName: "ping", schema: schema, models: [model])
                lines.append("\(model) : répond")
            } catch let error as LLMError {
                lines.append("\(model) : " + (error == .rateLimited ? "quota atteint" : error.userMessage))
                if error == .unauthorized { break }
            } catch {
                lines.append("\(model) : " + LLMError.network.userMessage)
            }
        }
        return lines
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
        let stored = ((try? context.fetch(FetchDescriptor<Run>())) ?? [])
            .filter { !$0.isStrength && $0.distanceM > 0 && $0.durationS > 0 }
        func summary(_ run: Run) -> RunSummary {
            RunSummary(date: run.startDate, distanceM: run.distanceM, durationS: run.durationS,
                       perceivedEffort: run.perceivedEffort, hrZoneSeconds: run.hrZoneSeconds, avgHR: run.avgHR)
        }
        let runs = stored.map(summary)
        // Tracés des 6 dernières semaines seulement : les décoder coûte, le bilan n'en a pas besoin de plus.
        let sixWeeksAgo = DayKey.addDays(-43, to: today)
        let detailed = stored.filter { $0.startDate >= sixWeeksAgo }.map {
            AnalyzedRun(summary: summary($0), track: $0.loadTrack(), avgCadenceSpm: $0.avgCadenceSpm, elevationGainM: $0.elevationGainM)
        }
        let weekAgo = DayKey.key(DayKey.addDays(-7, to: today))
        let metrics = ((try? context.fetch(FetchDescriptor<DailyMetric>())) ?? [])
            .filter { $0.dayKey >= weekAgo }
            .sorted { $0.dayKey < $1.dayKey }
        let sleep = metrics.compactMap(\.sleepSeconds)
        let age = DayKey.calendar.dateComponents([.year], from: profile.birthDate, to: today).year ?? 30
        let missedSince = DayKey.key(DayKey.addDays(-14, to: today))
        let missed = ((try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? [])
            .filter { $0.status == "missed" && $0.dayKey >= missedSince }.count
        var input = SnapshotBuilder.Input(
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
        input.detailedRuns = detailed
        return input
    }

    // MARK: - Bilan et chat

    /// Bilan de forme des 6 dernières semaines, pour l'onglet Progrès (nil sans profil ni sortie récente).
    func analysis() -> FitnessAnalysis? {
        let context = container.mainContext
        guard let profile = (try? context.fetch(FetchDescriptor<AthleteProfile>()))?.first else { return nil }
        let goal = (try? context.fetch(FetchDescriptor<Goal>()))?.first { $0.isActive }
        return SnapshotBuilder.analysis(snapshotInput(profile: profile, goal: goal, context: context, today: Date()))
    }

    /// Envoie un message au coach. La réponse est enregistrée ; une douleur ou une fatigue déclarée agit tout de suite
    /// sur le profil (§6.6), sans attendre de confirmation.
    func send(_ text: String) async {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isReplying else { return }
        let context = container.mainContext
        let history = ((try? context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            .suffix(12).map { LLMMessage(role: $0.role, content: $0.text) }
        context.insert(ChatMessage(role: "user", text: message))
        try? context.save()
        chatError = nil
        guard let llm = client() else {
            chatError = LLMError.missingKey.userMessage
            return
        }
        guard let profile = (try? context.fetch(FetchDescriptor<AthleteProfile>()))?.first else {
            chatError = "Termine d'abord la configuration."
            return
        }
        isReplying = true
        defer { isReplying = false }
        let goal = (try? context.fetch(FetchDescriptor<Goal>()))?.first { $0.isActive }
        let today = Date()
        let snapshot = SnapshotBuilder.snapshot(snapshotInput(profile: profile, goal: goal, context: context, today: today))
        let label = today.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "fr_FR")))
        do {
            let response = try await CoachEngine.chat(llm: llm, todayLabel: label, snapshot: snapshot,
                                                      upcoming: upcoming(context: context, today: today),
                                                      history: Array(history), message: message)
            context.insert(ChatMessage(role: "assistant", text: response.reply))
            let patch = response.profilePatch
            if let pain = patch.currentPain { profile.currentPain = pain }
            if let fatigue = patch.fatigueLevel { profile.fatigueLevel = fatigue }
            if let note = patch.injuryNote, !note.isEmpty { profile.injuryNote = note }
            profile.updatedAt = Date()
            try? context.save()
        } catch let error as LLMError {
            chatError = error.userMessage
        } catch {
            chatError = LLMError.network.userMessage
        }
    }

    /// Séances des 14 prochains jours, détail complet, avec le nom français des exercices de renfo.
    private func upcoming(context: ModelContext, today: Date) -> String {
        let from = DayKey.key(today)
        let to = DayKey.key(DayKey.addDays(14, to: today))
        let rows: [[String: Any]] = ((try? context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.dayKey)]))) ?? [])
            .filter { $0.dayKey >= from && $0.dayKey <= to && $0.status != "cancelled" }
            .compactMap { w in
                guard var spec = (try? JSONSerialization.jsonObject(with: w.specData)) as? [String: Any] else { return nil }
                spec["status"] = w.status
                if let exercises = w.spec?.exercises, !exercises.isEmpty {
                    spec["exercise_names"] = Dictionary(exercises.map { ($0.exerciseId, StrengthNames.name($0.exerciseId)) }) { a, _ in a }
                }
                return spec
            }
        let data = (try? JSONSerialization.data(withJSONObject: rows)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
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
