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

    /// shortcut: la course elle-même n'est pas ajoutée à la semaine de course par l'IA ; à faire avec la régénération hebdomadaire (4.7).
    public static func generateWeek(llm: LLMClient?, snapshot: AthleteSnapshot, brief: WeekBrief, recentPlan: String) async -> WeekResult {
        let easy = Guardrails.easyPaceSPerKm(snapshot)
        func fallback(_ notice: String) -> WeekResult {
            WeekResult(workouts: FallbackPlanner.week(brief: brief, snapshot: snapshot), summary: nil, source: "fallback", notice: notice)
        }
        /// Réponse décodée et normalisée, ou la liste des problèmes à faire corriger.
        func check(_ text: String) -> Result<WeekPlanResponse, Problems> {
            guard var plan = try? JSONDecoder().decode(WeekPlanResponse.self, from: Data(text.utf8)) else {
                return .failure(Problems(lines: ["la réponse n'est pas un objet JSON conforme au schéma"]))
            }
            plan.workouts = plan.workouts.map { normalized($0, easyPaceSPerKm: easy) }.sorted { $0.date < $1.date }
            let violations = Guardrails.validate(week: plan.workouts, brief: brief, snapshot: snapshot)
            return violations.isEmpty ? .success(plan) : .failure(Problems(lines: violations.map(\.description)))
        }

        guard let llm else { return fallback(LLMError.missingKey.userMessage) }
        var messages = [LLMMessage(role: "user", content: Prompts.weekPlan(snapshot: snapshot, brief: brief, recentPlan: recentPlan))]
        do {
            let first = try await llm.complete(system: Prompts.systemBase, messages: messages,
                                               schemaName: "week_plan", schema: CoachSchemas.weekPlan)
            switch check(first) {
            case .success(let plan):
                return WeekResult(workouts: plan.workouts, summary: plan.summary, source: "ai", notice: nil)
            case .failure(let problems):
                messages += [LLMMessage(role: "assistant", content: first), LLMMessage(role: "user", content: Prompts.repair(problems.lines))]
            }
            let second = try await llm.complete(system: Prompts.systemBase, messages: messages,
                                                schemaName: "week_plan", schema: CoachSchemas.weekPlan)
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

    /// Une réponse du chat. Valeurs hors liste ramenées à nil ou `none` : seul le code décide de ce qui touche le profil.
    public static func chat(llm: LLMClient, todayLabel: String, snapshot: AthleteSnapshot, upcoming: String,
                            history: [LLMMessage], message: String) async throws -> ChatResponse {
        let text = try await llm.complete(
            system: Prompts.chatSystem,
            messages: [LLMMessage(role: "user", content: Prompts.chatMessage(todayLabel: todayLabel, snapshot: snapshot, upcoming: upcoming,
                                                                             history: Array(history.suffix(12)), message: message))],
            schemaName: "chat_response", schema: CoachSchemas.chat, tier: Prompts.chatTier(message))
        guard var response = try? JSONDecoder().decode(ChatResponse.self, from: Data(text.utf8)),
              !response.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidOutput
        }
        if let level = response.profilePatch.fatigueLevel, !["low", "normal", "high"].contains(level) {
            response.profilePatch.fatigueLevel = nil
        }
        if !["none", "pain", "medical"].contains(response.safety) { response.safety = "none" }
        // Douleur ou symptôme déclaré : le mode prudent s'active même si l'IA a oublié le champ.
        if response.safety != "none" { response.profilePatch.currentPain = true }
        return response
    }

    struct Problems: Error {
        let lines: [String]
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
