import Foundation
import SwiftData
import RunCoachCore

/// Jeu de données factices déterministe (étape 1 et captures d'écran de la CI).
/// Tout est daté par rapport à aujourd'hui pour que les écrans soient toujours remplis.
/// Les tracés sont synthétiques : une boucle fictive dans un grand parc public, aucun lieu personnel.
enum MockData {
    @MainActor
    static func seed(into context: ModelContext) {
        let today = DayKey.calendar.startOfDay(for: Date())

        // Profil et objectif de l'utilisateur de référence (ARCHITECTURE.md §0.1).
        let profile = AthleteProfile(
            firstName: "Sam",
            birthDate: DayKey.calendar.date(byAdding: .year, value: -21, to: today) ?? today,
            runningSince: DayKey.addDays(-56, to: today)
        )
        profile.medicalDisclaimerAcceptedAt = today
        context.insert(profile)

        let goal = Goal(
            name: "Semi-marathon",
            raceDistanceM: 21097.5,
            raceDate: DayKey.date("2027-05-16"),
            targetTimeS: 7200
        )
        context.insert(goal)

        // 8 semaines de sorties : 3 par semaine, volume et allure en progression.
        var runsByDaysAgo: [Int: Run] = [:]
        var activityId: Int64 = 9_000_000
        for week in 0..<8 {
            for dayInWeek in [2, 4, 7] {
                let daysAgo = week * 7 + dayInWeek
                let progress = 1 - Double(daysAgo) / 58
                let isLong = dayInWeek == 7
                let distanceM = ((3500 + 2600 * progress) * (isLong ? 1.3 : 1.0) / 100).rounded() * 100
                let paceSPerKm = 418 - 26 * progress + (isLong ? 10 : 0)
                activityId += 1
                runsByDaysAgo[daysAgo] = makeRun(
                    in: context,
                    id: activityId,
                    daysAgo: daysAgo,
                    today: today,
                    distanceM: distanceM,
                    paceSPerKm: paceSPerKm,
                    name: isLong ? "Sortie longue" : "Footing"
                )
            }
        }

        // Métriques quotidiennes des 7 derniers jours.
        for daysAgo in 0..<7 {
            let metric = DailyMetric(dayKey: DayKey.key(DayKey.addDays(-daysAgo, to: today)))
            metric.sleepSeconds = 7.1 * 3600 + Double((daysAgo * 37) % 50) * 60
            metric.restingHR = 56 + daysAgo % 3
            metric.vo2max = 44
            context.insert(metric)
        }

        // Plan : la semaine passée, aujourd'hui, les 10 prochains jours.
        let plan = TrainingPlan(goal: goal, macroWeeks: [
            MacroWeek(weekStart: DayKey.key(DayKey.weekStart(today)), phase: .base, targetKm: 16.5,
                      longRunKm: 7, sessions: 3, qualitySessions: 0, isCutback: false)
        ])
        context.insert(plan)

        func add(_ spec: WorkoutSpec, status: String = "planned", sync: String = "notSent", daysAgo: Int? = nil) {
            let workout = PlannedWorkout(spec: spec, status: status, garminSyncState: sync)
            context.insert(workout)
            workout.plan = plan
            if let daysAgo = daysAgo, let run = runsByDaysAgo[daysAgo] {
                run.plannedWorkout = workout
            }
        }

        func key(_ offset: Int) -> String { DayKey.key(DayKey.addDays(offset, to: today)) }

        add(longRun(key(-7), km: 6.5), status: "done", sync: "sent", daysAgo: 7)
        add(strength(key(-5)), status: "done")
        add(easy(key(-4), minutes: 35, km: 5.0), status: "done", sync: "sent", daysAgo: 4)
        add(easy(key(-2), minutes: 35, km: 5.2), status: "done", sync: "sent", daysAgo: 2)
        add(recovery(key(-1)), status: "missed", sync: "sent")
        add(easyWithStrides(key(0)), sync: "sent")
        add(strength(key(1)))
        add(longRun(key(3), km: 7.0), sync: "sent")
        add(easy(key(5), minutes: 35, km: 5.2), sync: "sent")
        add(intervals(key(7)))
        add(strength(key(8)))
        add(longRun(key(10), km: 8.0))

        // Conversation avec le coach.
        let base = Date().addingTimeInterval(-3600)
        context.insert(ChatMessage(role: "user", text: "Salut ! J'ai les jambes lourdes depuis hier, je fais quoi demain ?", createdAt: base))
        context.insert(ChatMessage(
            role: "assistant",
            text: "Jambes lourdes après ta sortie de mardi, c'est normal à ce stade. On garde le footing d'aujourd'hui mais on enlève les accélérations, et je décale ta sortie longue d'un jour pour te laisser récupérer.",
            createdAt: base.addingTimeInterval(20),
            actionLines: [
                "Aujourd'hui : footing 35 min, sans lignes droites",
                "Sortie longue 7 km : samedi → dimanche"
            ],
            actionsState: "proposed"
        ))

        let sync = SyncState()
        sync.lastGarminSyncAt = Date().addingTimeInterval(-1200)
        sync.backfillDone = true
        context.insert(sync)
    }

    // MARK: - Sorties

    @MainActor
    private static func makeRun(in context: ModelContext, id: Int64, daysAgo: Int, today: Date,
                                distanceM: Double, paceSPerKm: Double, name: String) -> Run {
        let start = DayKey.addDays(-daysAgo, to: today).addingTimeInterval(18.5 * 3600)
        let durationS = (distanceM / 1000 * paceSPerKm).rounded()
        let run = Run(garminActivityId: id, name: name, startDate: start, distanceM: distanceM, durationS: durationS)
        // Insérer avant de toucher aux relations : SwiftData gère mal les relations entre objets non insérés.
        context.insert(run)
        run.movingDurationS = durationS
        run.avgSpeedMps = distanceM / durationS
        run.maxSpeedMps = distanceM / durationS * 1.25
        run.avgHR = 152 + (daysAgo % 5)
        run.maxHR = 174 + (daysAgo % 4)
        run.avgCadenceSpm = 164
        run.elevationGainM = (distanceM / 1000 * 7).rounded()
        run.elevationLossM = (distanceM / 1000 * 7).rounded()
        run.calories = (distanceM / 1000 * 68).rounded()
        run.avgTemperatureC = 9
        run.vo2max = 44
        run.aerobicTE = 2.8
        run.hrZoneSeconds = [durationS * 0.06, durationS * 0.34, durationS * 0.42, durationS * 0.16, durationS * 0.02]
        run.edwardsLoad = (durationS / 60 * 2.7).rounded()
        run.locationName = "Parc"
        run.detailState = "complete"
        run.perceivedEffort = 5

        let track = makeTrack(distanceM: distanceM, paceSPerKm: paceSPerKm)
        let runTrack = RunTrack(track: track)
        run.track = runTrack

        let fullKm = Int(distanceM / 1000)
        for km in 0..<fullKm {
            let wave = sin(Double(km) * 1.3 + Double(daysAgo))
            let split = Split(index: km + 1, distanceM: 1000, durationS: (paceSPerKm * (1 + 0.035 * wave)).rounded())
            split.avgHR = 146 + km * 2
            split.avgCadenceSpm = 163 + Double(km % 3)
            split.elevationGainM = 7
            split.avgSpeedMps = 1000 / split.durationS
            run.splits.append(split)
        }
        return run
    }

    /// Boucle fermée synthétique, un point toutes les 5 secondes environ.
    private static func makeTrack(distanceM: Double, paceSPerKm: Double) -> Track {
        let durationS = distanceM / 1000 * paceSPerKm
        let n = max(60, Int(durationS / 5))
        let centerLat = 48.8300
        let centerLon = 2.4350
        let radiusM = distanceM / (2 * Double.pi)
        var track = Track(t: [], lat: [], lon: [], dist: [], ele: [], hr: [], cad: [], speed: [])
        for i in 0..<n {
            let f = Double(i) / Double(n - 1)
            let angle = f * 2 * Double.pi
            let r = radiusM * (1 + 0.12 * sin(angle * 3) + 0.05 * sin(angle * 7))
            track.t.append(f * durationS)
            track.lat.append(centerLat + r * cos(angle) / 111_320)
            track.lon.append(centerLon + r * sin(angle) / (111_320 * cos(centerLat * Double.pi / 180)))
            track.dist.append(f * distanceM)
            track.ele?.append(52 + 9 * sin(angle * 2) + 3 * sin(angle * 5))
            track.hr?.append(138 + 26 * f + 4 * sin(angle * 9))
            track.cad?.append(163 + 4 * sin(angle * 4))
            track.speed?.append(1000 / (paceSPerKm * (1 + 0.07 * sin(angle * 6))))
        }
        return track
    }

    // MARK: - Séances

    private static let easyTarget = WorkoutTarget.pace(418, 461)

    private static func easy(_ date: String, minutes: Int, km: Double) -> WorkoutSpec {
        WorkoutSpec(
            date: date, kind: .easy, title: "Footing facile",
            rationale: "Allure où tu peux parler. C'est elle qui construit ton endurance pour le semi.",
            estimatedDurationMin: minutes, estimatedDistanceKm: km,
            blocks: [WorkoutBlock(steps: [
                WorkoutStep(intent: .run, end: .time, value: Double(minutes * 60), target: easyTarget)
            ])]
        )
    }

    private static func easyWithStrides(_ date: String) -> WorkoutSpec {
        WorkoutSpec(
            date: date, kind: .easy, title: "Footing + lignes droites",
            rationale: "Footing habituel, puis 6 accélérations courtes pour réveiller ta foulée sans te fatiguer.",
            estimatedDurationMin: 42, estimatedDistanceKm: 5.8,
            blocks: [
                WorkoutBlock(steps: [WorkoutStep(intent: .warmup, end: .time, value: 300, note: "Très facile")]),
                WorkoutBlock(steps: [WorkoutStep(intent: .run, end: .time, value: 1500, target: easyTarget)]),
                WorkoutBlock(repeatCount: 6, steps: [
                    WorkoutStep(intent: .run, end: .time, value: 20, note: "Vite mais relâché"),
                    WorkoutStep(intent: .recover, end: .time, value: 60, note: "Marche")
                ]),
                WorkoutBlock(steps: [WorkoutStep(intent: .cooldown, end: .time, value: 300)])
            ]
        )
    }

    private static func longRun(_ date: String, km: Double) -> WorkoutSpec {
        WorkoutSpec(
            date: date, kind: .long, title: "Sortie longue",
            rationale: "Un kilomètre de plus que la dernière fois. On allonge doucement, sans regarder l'allure.",
            estimatedDurationMin: Int(km * 7.3), estimatedDistanceKm: km,
            blocks: [WorkoutBlock(steps: [
                WorkoutStep(intent: .run, end: .distance, value: km * 1000, target: .pace(418, 468))
            ])]
        )
    }

    private static func recovery(_ date: String) -> WorkoutSpec {
        WorkoutSpec(
            date: date, kind: .recovery, title: "Récupération",
            rationale: "Très lent, juste pour faire circuler le sang après ta sortie longue.",
            estimatedDurationMin: 25, estimatedDistanceKm: 3.2,
            blocks: [WorkoutBlock(steps: [
                WorkoutStep(intent: .run, end: .time, value: 1500, target: .pace(461, 514))
            ])]
        )
    }

    private static func intervals(_ date: String) -> WorkoutSpec {
        WorkoutSpec(
            date: date, kind: .intervals, title: "Fractionné 6 × 400 m",
            rationale: "Première séance de vitesse : des efforts courts, plus rapides que ton allure cible du semi.",
            estimatedDurationMin: 42, estimatedDistanceKm: 6.0,
            blocks: [
                WorkoutBlock(steps: [WorkoutStep(intent: .warmup, end: .time, value: 600, note: "Très facile")]),
                WorkoutBlock(repeatCount: 6, steps: [
                    WorkoutStep(intent: .run, end: .distance, value: 400, target: .pace(325, 340)),
                    WorkoutStep(intent: .recover, end: .time, value: 90, note: "Marche ou trot")
                ]),
                WorkoutBlock(steps: [WorkoutStep(intent: .cooldown, end: .time, value: 600)])
            ]
        )
    }

    private static func strength(_ date: String) -> WorkoutSpec {
        WorkoutSpec(
            date: date, kind: .strength, title: "Renfo coureur",
            rationale: "Fessiers, mollets et gainage : ce qui protège tes genoux quand le volume monte.",
            estimatedDurationMin: 25, estimatedDistanceKm: nil,
            exercises: [
                StrengthExercise(exerciseId: "squat", sets: 3, reps: 12, restS: 60, note: "Descends lentement"),
                StrengthExercise(exerciseId: "glute_bridge", sets: 3, reps: 15, restS: 45),
                StrengthExercise(exerciseId: "calf_raise", sets: 3, reps: 15, restS: 45),
                StrengthExercise(exerciseId: "plank", sets: 3, durationS: 40, restS: 45),
                StrengthExercise(exerciseId: "side_plank", sets: 2, durationS: 30, restS: 30)
            ]
        )
    }
}

/// Noms français des exercices de renforcement (le catalogue complet arrive à l'étape 4).
enum StrengthNames {
    static let names: [String: String] = [
        "squat": "Squat",
        "lunge": "Fente",
        "step_up": "Montée sur marche",
        "glute_bridge": "Pont fessier",
        "hip_thrust": "Hip thrust",
        "single_leg_deadlift": "Soulevé de terre unijambiste",
        "calf_raise": "Montée sur pointes",
        "wall_sit": "Chaise",
        "plank": "Planche",
        "side_plank": "Planche latérale",
        "dead_bug": "Dead bug",
        "bird_dog": "Bird dog",
        "clamshell": "Coquillage",
        "superman": "Superman",
        "push_up": "Pompe",
        "mountain_climber": "Mountain climber"
    ]

    static func name(_ id: String) -> String {
        names[id] ?? id
    }
}
