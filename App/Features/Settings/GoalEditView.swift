import SwiftUI
import SwiftData
import RunCoachCore

/// Réglages → Objectif : course (distance, date, temps visé) ou progression sans échéance.
/// Modifié sur place : le plan jusqu'à la course est recalculé à la prochaine génération.
struct GoalEditView: View {
    @Environment(\.modelContext) private var context
    @Query private var goals: [Goal]

    var body: some View {
        Form {
            if let goal = goals.first(where: { $0.isActive }) {
                GoalFields(goal: goal)
            } else {
                Button("Choisir un objectif") {
                    context.insert(Goal(kind: "race", name: "Semi-marathon", raceDistanceM: 21_100,
                                        raceDate: DayKey.addDays(180, to: Date()), targetTimeS: 7200))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .rcScreenBackground()
        .navigationTitle("Objectif")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GoalFields: View {
    @Bindable var goal: Goal
    @Environment(CoachService.self) private var coach

    private static let distances: [(km: Double, name: String)] = [(5, "5 km"), (10, "10 km"), (21.1, "Semi-marathon"), (42.2, "Marathon")]

    var body: some View {
        Section {
            Picker("Type", selection: $goal.kind) {
                Text("Une course").tag("race")
                Text("Progresser").tag("fitness")
            }
            .pickerStyle(.segmented)
            .onChange(of: goal.kind) {
                if goal.kind == "race", goal.raceDistanceM == nil { setDistance(21.1) }
            }
        } footer: {
            Text(goal.kind == "race" ? "Le plan est construit à rebours depuis la date de la course." : "Cycles de 12 semaines pour monter ton volume progressivement, sans échéance.")
        }
        if goal.kind == "race" {
            Section("Course") {
                Picker("Distance", selection: Binding(get: { distanceKm }, set: setDistance)) {
                    ForEach(Self.distances, id: \.km) { Text($0.name).tag($0.km) }
                    Text("Autre").tag(0.0)
                }
                if !Self.distances.contains(where: { $0.km == distanceKm }) {
                    Stepper(Fmt.decimal(goal.raceDistanceM.map { $0 / 1000 } ?? 15, decimals: 1) + " km",
                            value: Binding(get: { (goal.raceDistanceM ?? 15_000) / 1000 }, set: { goal.raceDistanceM = $0 * 1000; goal.name = Fmt.decimal($0, decimals: 1) + " km" }),
                            in: 1...100, step: 0.5)
                }
                DatePicker("Date", selection: Binding(get: { goal.raceDate ?? DayKey.addDays(120, to: Date()) }, set: { goal.raceDate = $0 }),
                           in: Date()..., displayedComponents: .date)
            }
            Section {
                Toggle("J'ai un temps visé", isOn: Binding(get: { goal.targetTimeS != nil },
                                                          set: { goal.targetTimeS = $0 ? (goal.targetTimeS ?? 3600) : nil }))
                if let target = goal.targetTimeS {
                    Stepper("\(Int(target) / 3600) h", value: Binding(get: { Int(target) / 3600 },
                                                                    set: { goal.targetTimeS = Double($0 * 3600 + Int(target) % 3600) }), in: 0...12)
                    Stepper("\(Int(target) % 3600 / 60) min", value: Binding(get: { Int(target) % 3600 / 60 },
                                                                           set: { goal.targetTimeS = Double(Int(target) / 3600 * 3600 + $0 * 60) }), in: 0...59)
                    if let km = goal.raceDistanceM.map({ $0 / 1000 }), km > 0 {
                        Text("Allure visée : " + Fmt.pace(sPerKm: target / km) + " /km")
                            .foregroundStyle(Color.rc.textSecondary)
                    }
                }
            } header: {
                Text("Temps visé")
            } footer: {
                Text("Le coach te dira honnêtement si ce temps paraît hors de portée au vu de tes sorties.")
            }
        }
        Section {
            Button {
                Task { await coach.generateNextWeek() }
            } label: {
                HStack {
                    Text("Mettre à jour mon plan")
                    if coach.isGenerating {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(coach.isGenerating)
        } footer: {
            Text("Recalcule le plan jusqu'à l'objectif et régénère la semaine prochaine.")
        }
    }

    private var distanceKm: Double {
        let km = (goal.raceDistanceM ?? 21_100) / 1000
        return Self.distances.contains { $0.km == km } ? km : 0
    }

    private func setDistance(_ km: Double) {
        if let preset = Self.distances.first(where: { $0.km == km }) {
            goal.raceDistanceM = km * 1000
            goal.name = preset.name
        } else {
            goal.raceDistanceM = 15_000
            goal.name = "15 km"
        }
        if goal.raceDate == nil { goal.raceDate = DayKey.addDays(120, to: Date()) }
    }
}

/// Réglages → Entraînement : jours disponibles, sortie longue, durée des séances, renfo.
struct TrainingSettingsView: View {
    @Query private var profiles: [AthleteProfile]

    var body: some View {
        Form {
            if let profile = profiles.first {
                TrainingFields(profile: profile)
            }
        }
        .scrollContentBackground(.hidden)
        .rcScreenBackground()
        .navigationTitle("Entraînement")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TrainingFields: View {
    @Bindable var profile: AthleteProfile

    var body: some View {
        Section {
            WeekdayPicker(selection: $profile.availableWeekdays)
            Picker("Sortie longue", selection: $profile.longRunWeekday) {
                ForEach(profile.availableWeekdays.isEmpty ? Array(1...7) : profile.availableWeekdays, id: \.self) { day in
                    Text(WeekdayPicker.names[day - 1]).tag(day)
                }
            }
        } header: {
            Text("Jours où tu peux courir")
        } footer: {
            Text("Le plan place 3 séances en fondation, jusqu'à 4 ensuite, jamais plus que tes jours disponibles. Tu peux aussi demander au coach de déplacer une séance un autre jour.")
        }
        Section {
            Stepper("\(profile.maxSessionMinutes) min", value: $profile.maxSessionMinutes, in: 20...180, step: 5)
        } header: {
            Text("Durée max d'une séance")
        } footer: {
            Text("La sortie longue n'est pas limitée par cette durée.")
        }
        Section("Renforcement") {
            Toggle("Inclure du renfo", isOn: $profile.wantsStrength)
            if profile.wantsStrength {
                Picker("Matériel", selection: $profile.strengthEquipment) {
                    Text("Aucun").tag("none")
                    Text("Haltères").tag("dumbbells")
                    Text("Salle").tag("gym")
                }
            }
        }
        .onChange(of: profile.availableWeekdays) {
            // La sortie longue doit tomber un jour disponible.
            if !profile.availableWeekdays.isEmpty, !profile.availableWeekdays.contains(profile.longRunWeekday) {
                profile.longRunWeekday = profile.availableWeekdays.last ?? 7
            }
        }
    }
}

/// Réglages → Santé : douleur, fatigue, antécédents. Une douleur déclarée allège le plan (G11).
struct HealthSettingsView: View {
    @Query private var profiles: [AthleteProfile]

    var body: some View {
        Form {
            if let profile = profiles.first {
                HealthFields(profile: profile)
            }
        }
        .scrollContentBackground(.hidden)
        .rcScreenBackground()
        .navigationTitle("Santé")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HealthFields: View {
    @Bindable var profile: AthleteProfile

    var body: some View {
        Section {
            Toggle("Douleur en ce moment", isOn: $profile.currentPain)
            Picker("Fatigue", selection: $profile.fatigueLevel) {
                Text("Faible").tag("low")
                Text("Normale").tag("normal")
                Text("Élevée").tag("high")
            }
        } footer: {
            Text("Douleur : uniquement repos ou récupération courte jusqu'à ce que tu la retires. Fatigue élevée : pas de séance intense et 20 % de volume en moins. En cas de douleur qui persiste, consulte un médecin ou un kiné.")
        }
        Section {
            TextField("Ex. : tendinite au genou droit en 2025", text: $profile.injuryNote, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text("Blessures ou antécédents")
        } footer: {
            Text("Ce texte est envoyé au coach IA tel quel.")
        }
    }
}
