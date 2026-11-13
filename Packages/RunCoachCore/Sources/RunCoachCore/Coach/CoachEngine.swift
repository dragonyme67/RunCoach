import Foundation

/// Génération d'une semaine (F2, ARCHITECTURE.md §2.2 et §5.5) : IA, puis un appel de réparation, puis plan de secours.
/// Rien de ce que produit l'IA n'est gardé sans passer par `Guardrails`.
public enum CoachEngine {
    public struct WeekResult: Sendable {
        public var workouts: [WorkoutSpec]
        public var summary: String?
        /// `ai` ou `fallback`, recopié dans `PlannedWorkout.source`.
        public var source: String
        /// Pourquoi le plan de secours a servi, à montrer à l'utilisateur ; nil si l'IA a réussi.
        public var notice: String?
    }

    /// Semaine de course : la course elle-même est posée par le code le `raceDay`, jamais par l'IA.
    public static func generateWeek(llm: LLMClient?, snapshot: AthleteSnapshot, brief: WeekBrief, recentPlan: String,
                                    raceDay: String? = nil, raceDistanceKm: Double? = nil) async -> WeekResult {
        let easy = Guardrails.easyPaceSPerKm(snapshot)
        func fallback(_ notice: String) -> WeekResult {
            WeekResult(workouts: FallbackPlanner.week(brief: brief, snapshot: snapshot, raceDay: raceDay, raceDistanceKm: raceDistanceKm),
                       summary: nil, source: "fallback", notice: notice)
        }
        /// Réponse décodée et normalisée, ou la liste des problèmes à faire corriger.
        func check(_ text: String) -> Result<WeekPlanResponse, Problems> {
            guard var plan = try? JSONDecoder().decode(WeekPlanResponse.self, from: Data(text.utf8)) else {
                return .failure(Problems(lines: ["la réponse n'est pas un objet JSON conforme au schéma"]))
            }
            plan.workouts = plan.workouts.filter { $0.kind != .race }.map { normalized($0, easyPaceSPerKm: easy) }
            if let raceDay, let km = raceDistanceKm {
                plan.workouts.append(FallbackPlanner.race(day: raceDay, distanceKm: km, easyPaceSPerKm: easy))
            }
            plan.workouts.sort { $0.date < $1.date }
            let violations = Guardrails.validate(week: plan.workouts, brief: brief, snapshot: snapshot)
            return violations.isEmpty ? .success(plan) : .failure(Problems(lines: violations.map(\.description)))
        }

        guard let llm else { return fallback(LLMError.missingKey.userMessage) }
        // Au-delà, plan de secours : un modèle saturé peut faire attendre plusieurs minutes sans rien produire.
        let deadline = Date().addingTimeInterval(150)
        var messages = [LLMMessage(role: "user", content: Prompts.weekPlan(snapshot: snapshot, brief: brief, recentPlan: recentPlan))]
        do {
            let first = try await llm.complete(system: Prompts.systemBase, messages: messages,
                                               schemaName: "week_plan", schema: CoachSchemas.weekPlan, deadline: deadline)
            switch check(first) {
            case .success(let plan):
                return WeekResult(workouts: plan.workouts, summary: plan.summary, source: "ai", notice: nil)
            case .failure(let problems):
                messages += [LLMMessage(role: "assistant", content: first), LLMMessage(role: "user", content: Prompts.repair(problems.lines))]
            }
            let second = try await llm.complete(system: Prompts.systemBase, messages: messages,
                                                schemaName: "week_plan", schema: CoachSchemas.weekPlan, deadline: deadline)
            if case .success(let plan) = check(second) {
                return WeekResult(workouts: plan.workouts, summary: plan.summary, source: "ai", notice: nil)
            }
            return fallback("La proposition de l'IA dépassait tes limites de sécurité : plan généré sans IA.")
        } catch let error as LLMError {
            return fallback(error.userMessage)
        } catch {
            return fallback(LLMError.network.userMessage)
        }
    }

    public struct ChatOutcome: Sendable {
        /// Réponse nettoyée ; `actions` validées par les garde-fous, ou vides si elles ne passent pas.
        public var response: ChatResponse
        /// Résumé des actions pour la carte de confirmation.
        public var actionLines: [String]
    }

    /// Une réponse du chat (§6.6). Les actions proposées sont simulées sur une copie du plan puis validées ;
    /// en cas de violation, une réparation, puis abandon des actions. Valeurs hors liste ramenées à nil ou `none` :
    /// seul le code décide de ce qui touche le profil.
    /// `planned` : séances de la semaine en cours et de la suivante ; `briefs` : leurs cahiers des charges.
    public static func chat(llm: LLMClient, todayLabel: String, todayKey: String, snapshot: AthleteSnapshot, upcoming: String,
                            planned: [WorkoutSpec], briefs: [WeekBrief], history: [LLMMessage], message: String) async throws -> ChatOutcome {
        let tier = Prompts.chatTier(message)
        let easy = Guardrails.easyPaceSPerKm(snapshot)
        let briefs = briefs.map(chatBrief)
        var messages = [LLMMessage(role: "user", content: Prompts.chatMessage(
            todayLabel: todayLabel, snapshot: snapshot, upcoming: upcoming, briefs: tier == .hard ? briefs : [],
            history: Array(history.suffix(12)), message: message))]

        func ask() async throws -> (text: String, response: ChatResponse) {
            let text = try await llm.complete(system: Prompts.chatSystem, messages: messages, schemaName: "chat_response",
                                              schema: tier == .hard ? CoachSchemas.chatWithActions : CoachSchemas.chat, tier: tier)
            guard var response = try? JSONDecoder().decode(ChatResponse.self, from: Data(text.utf8)),
                  !response.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMError.invalidOutput
            }
            response.actions = response.actions.map { action in
                var action = action
                action.workout = action.workout.map { normalized($0, easyPaceSPerKm: easy) }
                return action
            }
            return (text, response)
        }
        /// Lignes de la carte de confirmation, ou les problèmes à faire corriger.
        func check(_ actions: [PlanAction]) -> Result<[String], Problems> {
            let outcome = PlanActions.apply(actions, to: planned, todayKey: todayKey)
            var problems = outcome.problems
            let touched = Set(actions.flatMap { [$0.date] + ($0.newDate.map { [$0] } ?? []) }
                .compactMap { DayKey.date($0).map { DayKey.key(DayKey.weekStart($0)) } })
            for weekStart in touched.sorted() {
                guard let brief = briefs.first(where: { $0.weekStart == weekStart }) else {
                    problems.append("pas de plan défini pour la semaine du \(weekStart) : aucune modification possible")
                    continue
                }
                let week = outcome.specs.filter { $0.date >= weekStart && $0.date < Guardrails.dayAfterWeek(weekStart) }
                problems += Guardrails.validate(week: week, brief: brief, snapshot: snapshot).map(\.description)
            }
            return problems.isEmpty ? .success(outcome.lines) : .failure(Problems(lines: problems))
        }

        let first = try await ask()
        let text = first.text
        var response = first.response
        var lines: [String] = []
        if !response.actions.isEmpty {
            switch check(response.actions) {
            case .success(let ok):
                lines = ok
            case .failure(let problems):
                messages += [LLMMessage(role: "assistant", content: text), LLMMessage(role: "user", content: Prompts.repair(problems.lines))]
                var reasons = problems.lines
                if let second = try? await ask() {
                    switch check(second.response.actions) {
                    case .success(let ok):
                        response = second.response
                        lines = ok
                        reasons = []
                    case .failure(let again):
                        reasons = again.lines
                    }
                }
                if !reasons.isEmpty {
                    response.actions = []
                    response.reply += "\n\nJe ne peux pas faire ce changement, il casserait une règle de sécurité : "
                        + reasons.prefix(2).map(readable).joined(separator: " ; ") + "."
                }
            }
        }
        if let level = response.profilePatch.fatigueLevel, !["low", "normal", "high"].contains(level) {
            response.profilePatch.fatigueLevel = nil
        }
        if !["none", "pain", "medical"].contains(response.safety) { response.safety = "none" }
        // Douleur ou symptôme déclaré : le mode prudent s'active même si l'IA a oublié le champ.
        if response.safety != "none" { response.profilePatch.currentPain = true }
        // Symptôme inquiétant : aucune séance proposée (§6.5).
        if response.safety == "medical" {
            response.actions = []
            lines = []
        }
        return ChatOutcome(response: response, actionLines: lines)
    }

    struct Problems: Error {
        let lines: [String]
    }

    /// Dans le chat, une demande explicite de l'athlète peut sortir de ses préférences (jours disponibles, jour de la
    /// sortie longue, nombre de séances de renfo), jamais des règles de sécurité : volume, progression, jours durs,
    /// repos, allures, douleur (demande de l'utilisateur, 2026-11-13 : « pouvoir adapter mes séances »).
    static func chatBrief(_ brief: WeekBrief) -> WeekBrief {
        var b = brief
        if let start = DayKey.date(b.weekStart) {
            b.availableDays = (0..<7).map { DayKey.key(DayKey.addDays($0, to: start)) }
        }
        b.longRunDay = nil
        b.strengthSessions = max(b.strengthSessions, 3)
        b.strengthDays = b.availableDays
        for kind in [WorkoutKind.easy, .recovery, .strength] where !b.allowedKinds.contains(kind) {
            b.allowedKinds.append(kind)
        }
        return b
    }

    /// « G7, séance du 2026-11-16 : … » devient « séance du 2026-11-16 : … » pour l'athlète.
    static func readable(_ line: String) -> String {
        line.replacingOccurrences(of: #"^G\d+,? ?:? ?"#, with: "", options: .regularExpression)
    }

    /// Km et durée recalculés par le code (jamais ceux de l'IA), textes coupés aux longueurs du schéma.
    static func normalized(_ w: WorkoutSpec, easyPaceSPerKm: Double) -> WorkoutSpec {
        var w = w
        w.title = String(w.title.prefix(40))
        w.rationale = String(w.rationale.prefix(240))
        w.estimatedDurationMin = Int(Guardrails.durationMin(w, easyPaceSPerKm: easyPaceSPerKm).rounded())
        w.estimatedDistanceKm = w.kind.isRun ? (Guardrails.distanceKm(w, easyPaceSPerKm: easyPaceSPerKm) * 10).rounded() / 10 : nil
        return w
    }
}
