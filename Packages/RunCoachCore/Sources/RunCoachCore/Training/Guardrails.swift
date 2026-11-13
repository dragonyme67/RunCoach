import Foundation

/// Règle non respectée : identifiant (G1 à G13), séance concernée, message en français repris dans l'appel de réparation.
public struct Violation: Equatable, Sendable, CustomStringConvertible {
    public var rule: String
    public var date: String?
    public var message: String

    public var description: String {
        date.map { "\(rule), séance du \($0) : \(message)" } ?? "\(rule) : \(message)"
    }
}

/// Garde-fous (ARCHITECTURE.md §6.4) : tout ce que l'IA produit passe ici avant d'être enregistré.
/// Les km et durées sont recalculés à partir des blocs ; `estimated_distance_km` de l'IA n'est jamais cru.
public enum Guardrails {
    /// Tolérance d'arrondi sur les km.
    static let epsKm = 0.05

    public static func validate(week: [WorkoutSpec], brief: WeekBrief, snapshot: AthleteSnapshot) -> [Violation] {
        var out: [Violation] = []
        func add(_ rule: String, _ date: String?, _ message: String) {
            out.append(Violation(rule: rule, date: date, message: message))
        }
        let easy = easyPaceSPerKm(snapshot)
        // La course elle-même est hors volume et hors limites de durée (§6.3 : « course non comprise »).
        let runs = week.filter { $0.kind.isRun && $0.kind != .race }
        let total = runs.reduce(0) { $0 + distanceKm($1, easyPaceSPerKm: easy) }
        let recent = snapshot.lastWeeks.suffix(3)

        // G1, G2 : volume de la semaine.
        if total > brief.maxKm + epsKm {
            add("G1", nil, "total de course \(km(total)) km, au-dessus du maximum de \(km(brief.maxKm)) km")
        }
        // Sans historique, pas de G2 : le plafond du brief (G1) suffit.
        if let vmax = recent.map(\.km).max(), total > max(1.10 * vmax, vmax + 2) + epsKm {
            add("G2", nil, "total de course \(km(total)) km, plus de 10 % ou de 2 km au-dessus de la plus grosse semaine récente (\(km(vmax)) km)")
        }

        for w in runs where w.kind == .long {
            let d = distanceKm(w, easyPaceSPerKm: easy)
            if brief.longRunKm.count == 2, d > brief.longRunKm[1] + epsKm {
                add("G3", w.date, "sortie longue de \(km(d)) km, au-dessus de \(km(brief.longRunKm[1])) km")
            }
            if let longest = recent.map(\.longestKm).max(), d > longest + 2 + epsKm {
                add("G3", w.date, "sortie longue de \(km(d)) km, plus de 2 km au-dessus de la plus longue sortie récente (\(km(longest)) km)")
            }
            if d > 0.5 * total + epsKm {
                add("G3", w.date, "sortie longue de \(km(d)) km, plus de la moitié du volume de la semaine")
            }
        }

        // G4 : séances de qualité.
        let quality = week.filter { $0.kind == .tempo || $0.kind == .intervals }.count
        if quality > brief.maxQualitySessions {
            add("G4", nil, "\(quality) séances de tempo ou de fractionné, \(brief.maxQualitySessions) au plus")
        }

        // G5 : jamais deux jours durs de suite.
        let hardDays = Set(week.filter { $0.kind.isHard }.map(\.date))
        for day in hardDays.sorted() where hardDays.contains(nextDay(day)) {
            add("G5", nextDay(day), "deux séances dures de suite (\(day) et \(nextDay(day)))")
        }

        // G6 : jours sans aucune séance.
        let restNeeded = snapshot.athlete.isBeginner ? 2 : 1
        if 7 - Set(week.map(\.date)).count < restNeeded {
            add("G6", nil, "il faut au moins \(restNeeded) jour(s) sans aucune séance dans la semaine")
        }

        // G7 : jours de course.
        var runDays: Set<String> = []
        for w in runs {
            if !brief.availableDays.contains(w.date) {
                add("G7", w.date, "ce jour n'est pas un jour disponible pour courir")
            }
            if w.kind == .long, let day = brief.longRunDay, w.date != day {
                add("G7", w.date, "la sortie longue doit être le \(day)")
            }
            if !runDays.insert(w.date).inserted {
                add("G7", w.date, "une seule course par jour")
            }
        }

        let tempo = snapshot.pace(.tempo)
        let fastest = snapshot.pace(.intervals)?.fastSPerKm
        for w in runs {
            // G8 : durée. Sortie longue exemptée (choix de l'utilisateur, 2026-11-13 : pas de limite de durée) ;
            // sa distance reste bornée par G3.
            let minutes = durationMin(w, easyPaceSPerKm: easy)
            let limit = Double(brief.maxSessionMin)
            if w.kind != .long, minutes > limit + 0.5 {
                add("G8", w.date, "durée estimée \(Int(minutes.rounded())) min, \(Int(limit)) min au plus")
            }

            // G9 : allures dans la zone du type de séance ; rien de plus rapide que le fractionné.
            let zone = snapshot.pace(w.kind)
            var paceOK = true
            for block in w.blocks {
                for step in block.steps where step.target.type == .pace {
                    guard let lo = step.target.minSPerKm, let hi = step.target.maxSPerKm else { continue }
                    if let fastest, lo < fastest - 5 { paceOK = false }
                    if step.intent == .run, let zone, lo < zone.fastSPerKm - 5 || hi > zone.slowSPerKm + 5 { paceOK = false }
                }
            }
            if !paceOK {
                add("G9", w.date, "allure cible hors de la zone \(w.kind.rawValue) (paces_s_per_km)")
            }

            // G10 : volume rapide (allure tempo ou plus vite) dans une séance.
            if let tempo {
                var fastKm = 0.0
                for block in w.blocks {
                    for step in block.steps where step.target.type == .pace && (step.target.minSPerKm ?? .max) <= tempo.slowSPerKm + 5 {
                        fastKm += Double(max(1, block.repeatCount)) * stepKm(step, easyPaceSPerKm: easy)
                    }
                }
                let cap = max(2, 0.10 * brief.targetKm)
                if fastKm > cap + epsKm {
                    add("G10", w.date, "\(km(fastKm)) km à allure tempo ou plus rapide, \(km(cap)) km au plus")
                }
            }
        }

        // G11 : douleur ou grosse fatigue.
        if snapshot.athlete.currentPain {
            for w in week where w.kind != .recovery || durationMin(w, easyPaceSPerKm: easy) > 30.5 {
                add("G11", w.date, "douleur déclarée : uniquement de la récupération de 30 min au plus, ou du repos")
            }
        }
        if snapshot.athlete.fatigueLevel == "high" {
            if quality > 0 {
                add("G11", nil, "fatigue élevée : aucune séance de tempo ou de fractionné")
            }
            if total > 0.8 * brief.targetKm + epsKm {
                add("G11", nil, "fatigue élevée : \(km(0.8 * brief.targetKm)) km au plus cette semaine")
            }
        }

        // G12 : structure.
        let weekDays = DayKey.date(brief.weekStart).map { start in (0..<7).map { DayKey.key(DayKey.addDays($0, to: start)) } } ?? []
        for w in week {
            if !weekDays.contains(w.date) {
                add("G12", w.date, "date hors de la semaine du \(brief.weekStart)")
            }
            if !brief.allowedKinds.contains(w.kind) {
                add("G12", w.date, "type \(w.kind.rawValue) non autorisé cette semaine")
            }
            if let problem = structureProblem(w, easyPaceSPerKm: easy) {
                add("G12", w.date, problem)
            }
        }

        // G13 : renforcement.
        let strength = week.filter { $0.kind == .strength }
        if strength.count > brief.strengthSessions {
            add("G13", nil, "\(strength.count) séances de renforcement, \(brief.strengthSessions) au plus")
        }
        for w in strength {
            if durationMin(w, easyPaceSPerKm: easy) > 40.5 {
                add("G13", w.date, "renforcement de plus de 40 min")
            }
            if hardDays.contains(nextDay(w.date)) {
                add("G13", w.date, "renforcement la veille d'une séance dure")
            }
        }
        return out
    }

    // MARK: - Calculs

    /// Milieu de la zone `easy`, ou 7:00/km sans zones.
    public static func easyPaceSPerKm(_ snapshot: AthleteSnapshot) -> Double {
        snapshot.pace(.easy).map { Double($0.fastSPerKm + $0.slowSPerKm) / 2 } ?? 420
    }

    /// Km d'une séance d'après ses blocs : distance, ou durée × allure médiane de la cible, ou allure `easy` sans cible.
    public static func distanceKm(_ w: WorkoutSpec, easyPaceSPerKm: Double) -> Double {
        guard w.kind.isRun else { return 0 }
        return w.blocks.reduce(0) { sum, block in
            sum + Double(max(1, block.repeatCount)) * block.steps.reduce(0) { $0 + stepKm($1, easyPaceSPerKm: easyPaceSPerKm) }
        }
    }

    public static func durationMin(_ w: WorkoutSpec, easyPaceSPerKm: Double) -> Double {
        guard w.kind.isRun else {
            // Environ 3 s par répétition, plus la récupération entre les séries.
            let seconds = w.exercises.reduce(0) { sum, e in
                sum + Double(max(0, e.sets)) * (Double(e.reps ?? 0) * 3 + Double(e.durationS ?? 0) + Double(e.restS))
            }
            return seconds / 60
        }
        return w.segments(easyPaceSPerKm: easyPaceSPerKm).reduce(0) { $0 + $1.seconds } / 60
    }

    static func stepKm(_ step: WorkoutStep, easyPaceSPerKm: Double) -> Double {
        switch step.end {
        case .distance:
            return (step.value ?? 0) / 1000
        case .time, .lapButton:
            guard step.intent != .rest else { return 0 }
            var pace = easyPaceSPerKm
            if step.target.type == .pace, let lo = step.target.minSPerKm, let hi = step.target.maxSPerKm, lo + hi > 0 {
                pace = Double(lo + hi) / 2
            }
            return step.estimatedSeconds(easyPaceSPerKm: easyPaceSPerKm) / pace
        }
    }

    /// Première erreur de structure trouvée, ou nil.
    static func structureProblem(_ w: WorkoutSpec, easyPaceSPerKm: Double) -> String? {
        if w.kind == .strength {
            if w.exercises.isEmpty || !w.blocks.isEmpty { return "renforcement : des exercices, aucun bloc de course" }
            for e in w.exercises {
                if !StrengthCatalog.ids.contains(e.exerciseId) { return "exercice inconnu : \(e.exerciseId)" }
                if e.sets < 1 || e.restS < 0 { return "séries et récupération doivent être positives (\(e.exerciseId))" }
                if (e.reps ?? 0 > 0) == (e.durationS ?? 0 > 0) { return "répétitions ou durée, l'une des deux exactement (\(e.exerciseId))" }
            }
            return nil
        }
        if w.blocks.isEmpty || !w.exercises.isEmpty { return "course : au moins un bloc, aucun exercice" }
        for block in w.blocks {
            if !(1...20).contains(block.repeatCount) { return "répétitions entre 1 et 20" }
            if block.steps.isEmpty { return "bloc sans étape" }
            for step in block.steps {
                if step.end != .lapButton, (step.value ?? 0) <= 0 { return "durée ou distance d'étape positive" }
                switch step.target.type {
                case .pace:
                    guard let lo = step.target.minSPerKm, let hi = step.target.maxSPerKm, lo > 0, lo <= hi else {
                        return "cible d'allure : borne rapide puis borne lente, positives"
                    }
                case .hrZone:
                    if !(1...5).contains(step.target.hrZone ?? 0) { return "zone cardiaque entre 1 et 5" }
                case .none:
                    break
                }
            }
        }
        if w.kind == .tempo || w.kind == .intervals {
            let steps = w.blocks.flatMap(\.steps)
            func longest(_ intent: StepIntent) -> Double {
                steps.filter { $0.intent == intent }.map { $0.estimatedSeconds(easyPaceSPerKm: easyPaceSPerKm) }.max() ?? 0
            }
            if longest(.warmup) < 300 || longest(.cooldown) < 300 {
                return "échauffement et retour au calme d'au moins 5 min"
            }
        }
        return nil
    }

    static func nextDay(_ key: String) -> String {
        DayKey.date(key).map { DayKey.key(DayKey.addDays(1, to: $0)) } ?? key
    }

    private static func km(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
