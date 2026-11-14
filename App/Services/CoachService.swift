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
    /// Message préparé depuis un autre écran (« En parler au coach ») : l'onglet Coach s'ouvre et le reprend.
    var pendingDraft: String?
    /// Appelé quand des séances changent (génération, actions du chat) : envoi sur la montre (F3).
    @ObservationIgnored var onPlanChanged: (() -> Void)?

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
        // 45 s par essai : avec la limite globale de la génération, un modèle saturé ne bloque pas tout.
        let client = LLMClient(http: URLSessionHTTPClient(timeoutS: 45), provider: provider, apiKey: key) { line in
            let stamp = Date().formatted(date: .omitted, time: .standard)
            Task { @MainActor in self.addDiagnostic(line, stamp: stamp, provider: name) }
        }
        clients[providerId] = (key, client)
        return client
    }

    /// Pendant une génération : le modèle en cours d'essai, pour que l'attente ne paraisse pas vide.
    private(set) var generationStatus: String?

    private func addDiagnostic(_ line: String, stamp: String, provider: String) {
        if line.hasPrefix("→ ") {
            if isGenerating { generationStatus = "Essai avec " + line.dropFirst(2) + "…" }
            return
        }
        diagnostics.append("\(stamp) · \(provider) · \(line)")
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

    /// Lundi de la semaine que génère `generateNextWeek` : lundi prochain, ou aujourd'hui si on est lundi.
    private static func nextWeekStart(_ date: Date) -> Date {
        let monday = DayKey.weekStart(date)
        return DayKey.calendar.isDate(date, inSameDayAs: monday) ? monday : DayKey.addDays(7, to: monday)
    }

    /// Recalcule le plan jusqu'à la course à partir du volume réellement couru (§6.3, « recalcul chaque dimanche »),
    /// puis génère la semaine qui commence lundi prochain (aujourd'hui si on est lundi).
    /// Les séances encore prévues de cette semaine sont remplacées.
    func generateNextWeek() async {
        guard !isGenerating else { return }
        isGenerating = true
        defer {
            isGenerating = false
            generationStatus = nil
        }
        let context = container.mainContext
        guard let profile = (try? context.fetch(FetchDescriptor<AthleteProfile>()))?.first else {
            notice = "Termine d'abord la configuration."
            return
        }
        let goal = (try? context.fetch(FetchDescriptor<Goal>()))?.first { $0.isActive }
        let today = Date()
        let input = snapshotInput(profile: profile, goal: goal, context: context, today: today)
        let snapshot = SnapshotBuilder.snapshot(input)

        let start = Self.nextWeekStart(today)
        let startKey = DayKey.key(start)
        let plans = (try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []
        let plan: TrainingPlan
        if let active = plans.first(where: { $0.isActive && $0.goal?.uuid == goal?.uuid }) {
            plan = active
        } else {
            plans.forEach { $0.isActive = false }
            plan = TrainingPlan(goal: goal)
            context.insert(plan)
        }
        // L'allègement reste une semaine sur quatre depuis le début du plan, malgré le recalcul hebdomadaire.
        let origin = Self.nextWeekStart(plan.createdAt)
        let elapsed = max(0, (DayKey.calendar.dateComponents([.day], from: origin, to: start).day ?? 0) / 7)
        let days = max(2, profile.availableWeekdays.count)
        let base = SnapshotBuilder.baseline(input, sessionsPerWeek: min(days, 3))
        let race = goal?.kind == "race" ? goal : nil
        let upcoming = MacroPlanner.plan(MacroPlanner.Input(
            startWeek: start, raceDate: race?.raceDate, raceDistanceKm: race?.raceDistanceM.map { $0 / 1000 },
            v0Km: base.v0Km, l0Km: base.l0Km, availableDays: days, beginner: input.isBeginner, cycleOffset: elapsed))
        // Les semaines passées restent : le chat valide encore les changements de la semaine en cours avec elles.
        let weeks = plan.macroWeeks.filter { $0.weekStart < startKey } + upcoming
        plan.macroWeeksData = (try? JSONEncoder().encode(weeks)) ?? plan.macroWeeksData
        guard let week = upcoming.first(where: { $0.weekStart == startKey }),
              let brief = brief(for: week, profile: profile, goal: goal, snapshot: snapshot, beginner: input.isBeginner) else {
            notice = "Ta course est passée : choisis un nouvel objectif dans Réglages."
            return
        }

        let weekKeys = (0..<7).map { DayKey.key(DayKey.addDays($0, to: start)) }
        let raceDay = goal?.raceDate.map(DayKey.key).flatMap { weekKeys.contains($0) ? $0 : nil }
        let result = await CoachEngine.generateWeek(llm: client(), snapshot: snapshot, brief: brief,
                                                    recentPlan: recentPlan(context: context, today: today),
                                                    raceDay: raceDay, raceDistanceKm: race?.raceDistanceM.map { $0 / 1000 })

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
        onPlanChanged?()
    }

    /// Cahier des charges d'une semaine du plan.
    private func brief(for week: MacroWeek, profile: AthleteProfile, goal: Goal?, snapshot: AthleteSnapshot, beginner: Bool) -> WeekBrief? {
        guard let start = DayKey.date(week.weekStart) else { return nil }
        let weekKeys = (0..<7).map { DayKey.key(DayKey.addDays($0, to: start)) }
        let raceDay = goal?.raceDate.map(DayKey.key).flatMap { weekKeys.contains($0) ? $0 : nil }
        var input = WeekBriefBuilder.Input(
            week: week, availableWeekdays: profile.availableWeekdays, longRunWeekday: profile.longRunWeekday,
            maxSessionMin: profile.maxSessionMinutes, wantsStrength: profile.wantsStrength, beginner: beginner,
            loadRatio: snapshot.load.ratio, lastWeekKm: snapshot.lastWeeks.last?.km ?? 0, raceDay: raceDay)
        input.reducedLoad = snapshot.athlete.needsReducedLoad
        return WeekBriefBuilder.brief(input)
    }

    /// Une fois par jour à l'ouverture : le samedi, le dimanche ou le lundi, si la semaine à venir n'a pas encore
    /// de séances et qu'un plan existe déjà (le premier se lance à la main), elle est générée (4.7).
    func autoGenerateIfNeeded() async {
        let context = container.mainContext
        let today = Date()
        let weekday = DayKey.calendar.component(.weekday, from: today)   // 1 = dimanche, 2 = lundi, 7 = samedi
        let todayKey = DayKey.key(today)
        guard [1, 2, 7].contains(weekday), UserDefaults.standard.string(forKey: "coach.autoGenerated") != todayKey,
              ((try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []).contains(where: { $0.isActive }) else { return }
        let start = Self.nextWeekStart(today)
        let weekKeys = Set((0..<7).map { DayKey.key(DayKey.addDays($0, to: start)) })
        let workouts = (try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? []
        guard !workouts.contains(where: { weekKeys.contains($0.dayKey) && $0.status != "cancelled" }) else { return }
        UserDefaults.standard.set(todayKey, forKey: "coach.autoGenerated")
        await generateNextWeek()
    }

    /// Rattache les sorties aux séances du même jour et marque manquées les séances passées non faites (§4.3).
    func updatePlanStatus() {
        let context = container.mainContext
        let workouts = ((try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? []).filter { $0.status == "planned" }
        guard !workouts.isEmpty else { return }
        let earliest = workouts.map { $0.dayKey }.min() ?? ""
        let runs = ((try? context.fetch(FetchDescriptor<Run>())) ?? [])
            .filter { $0.plannedWorkout == nil && $0.dayKey >= earliest }
        let result = WorkoutMatcher.match(
            planned: workouts.map { WorkoutMatcher.Planned(dayKey: $0.dayKey, isRun: $0.kindValue.isRun, status: $0.status) },
            done: runs.map { WorkoutMatcher.Done(dayKey: $0.dayKey, isRun: !$0.isStrength) },
            todayKey: DayKey.key(Date()))
        for pair in result.pairs {
            runs[pair.done].plannedWorkout = workouts[pair.planned]
            workouts[pair.planned].status = "done"
            workouts[pair.planned].updatedAt = Date()
        }
        for index in result.missed {
            workouts[index].status = "missed"
            workouts[index].updatedAt = Date()
        }
        if !result.pairs.isEmpty || !result.missed.isEmpty { try? context.save() }
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
        input.painLevel = profile.painLevel
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
        let input = snapshotInput(profile: profile, goal: goal, context: context, today: today)
        let snapshot = SnapshotBuilder.snapshot(input)
        let label = today.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "fr_FR")))
        // Semaine en cours et suivante : les seules que le chat peut modifier, chacune avec ses bornes.
        let weekStarts = [DayKey.weekStart(today), DayKey.addDays(7, to: DayKey.weekStart(today))].map(DayKey.key)
        let macro = ((try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []).first { $0.isActive }?.macroWeeks ?? []
        let briefs = macro.filter { weekStarts.contains($0.weekStart) }
            .compactMap { brief(for: $0, profile: profile, goal: goal, snapshot: snapshot, beginner: input.isBeginner) }
        let end = DayKey.key(DayKey.addDays(14, to: DayKey.weekStart(today)))
        let planned = ((try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? [])
            .filter { $0.dayKey >= weekStarts[0] && $0.dayKey < end && $0.status != "cancelled" }
            .compactMap(\.spec)
        do {
            let outcome = try await CoachEngine.chat(llm: llm, todayLabel: label, todayKey: DayKey.key(today), snapshot: snapshot,
                                                     upcoming: upcoming(context: context, today: today), planned: planned,
                                                     briefs: briefs, history: Array(history), message: message)
            let response = outcome.response
            let reply = ChatMessage(role: "assistant", text: response.reply)
            if !response.actions.isEmpty {
                reply.actionsData = try? JSONEncoder().encode(response.actions)
                reply.actionLines = outcome.actionLines
                reply.actionsState = "proposed"
            }
            context.insert(reply)
            let patch = response.profilePatch
            // Niveau non précisé par l'IA : on garde celui déjà déclaré, sinon gêne légère (le coach demande de préciser).
            if let pain = patch.currentPain {
                profile.pain = pain ? (patch.painLevel ?? (profile.currentPain ? profile.pain : "mild")) : "none"
            }
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

    /// Applique les modifications proposées dans un message, après confirmation de l'athlète (§6.6).
    func applyActions(of message: ChatMessage) {
        guard message.actionsState == "proposed", let data = message.actionsData,
              let actions = try? JSONDecoder().decode([PlanAction].self, from: data) else { return }
        let context = container.mainContext
        let plan = ((try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []).first { $0.isActive }
        var workouts = ((try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? []).filter { $0.status == "planned" }
        for action in actions {
            /// Séance encore prévue ce jour-là, du même genre (course ou renfo) si on le connaît — comme `PlanActions.apply`.
            let target = workouts.first { $0.dayKey == action.date && (action.workout == nil || $0.kindValue.isRun == action.workout!.kind.isRun) }
                ?? workouts.first { $0.dayKey == action.date }
            switch action.op {
            case .add:
                guard var spec = action.workout else { continue }
                spec.date = action.date
                let workout = PlannedWorkout(spec: spec, source: "ai")
                context.insert(workout)
                workout.plan = plan
                workouts.append(workout)
            case .replace:
                guard var spec = action.workout, let target else { continue }
                spec.date = action.date
                target.update(with: spec, source: "ai")
            case .remove:
                target?.status = "cancelled"
                target?.updatedAt = Date()
                workouts.removeAll { $0 === target }
            case .move:
                guard let newDate = action.newDate, let target, var spec = target.spec else { continue }
                spec.date = newDate
                target.update(with: spec, source: target.source)
            }
        }
        message.actionsState = "applied"
        try? context.save()
        onPlanChanged?()
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
