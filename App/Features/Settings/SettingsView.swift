import SwiftUI
import SwiftData
import RunCoachCore

/// Réglages, ouverts dans la pile de l'écran Aujourd'hui (bouton retour et glissement natifs).
/// Tout ce qui façonne le plan est modifiable ici : objectif, disponibilités, profil, santé (demande de l'utilisateur, 2026-11-13).
struct SettingsView: View {
    @Query private var profiles: [AthleteProfile]
    @Query private var goals: [Goal]
    @Query private var syncStates: [SyncState]
    @Environment(SyncEngine.self) private var sync
    @Environment(CoachService.self) private var coach
    @State private var showOnboarding = false
    @State private var showGarminLogin = false

    var body: some View {
        Form {
            Section {
                NavigationLink(value: AppRoute.goal) {
                    row("Objectif", icon: "flag.checkered", value: goalSummary)
                }
                NavigationLink(value: AppRoute.training) {
                    row("Entraînement", icon: "calendar", value: trainingSummary)
                }
                NavigationLink(value: AppRoute.profile) {
                    row("Toi", icon: "person.fill", value: profiles.first.map { $0.firstName.isEmpty ? "" : $0.firstName } ?? "")
                }
                NavigationLink(value: AppRoute.health) {
                    row("Santé", icon: "cross.case.fill", value: ["mild": "Gêne légère", "severe": "Douleur nette"][profiles.first?.pain ?? "none"] ?? "")
                }
            } header: {
                Text("Ton plan")
            }

            Section {
                Button {
                    Task { await coach.generateNextWeek() }
                } label: {
                    HStack {
                        Text("Mettre à jour la semaine prochaine")
                        if coach.isGenerating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(coach.isGenerating)
                if coach.isGenerating, let status = coach.generationStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(Color.rc.textSecondary)
                }
                if let notice = coach.notice {
                    Text(notice)
                        .foregroundStyle(Color.rc.textSecondary)
                }
            } footer: {
                Text("Après un changement d'objectif, de jours ou de santé : le plan jusqu'à la course est recalculé et la semaine prochaine régénérée. Les séances déjà faites ne bougent pas.")
            }

            Section {
                NavigationLink(value: AppRoute.ai) {
                    row(coach.provider.name, icon: "sparkles", value: coach.hasKey ? "Clé enregistrée" : "Aucune clé")
                }
            } header: {
                Text("Coach IA")
            } footer: {
                Text("Sans clé, un plan de secours calculé sans IA est proposé. Seuls des résumés chiffrés sont envoyés au coach, jamais ta position.")
            }

            Section {
                HStack {
                    Label("Compte Garmin", systemImage: "applewatch")
                    Spacer()
                    Text(sync.isConnected ? (syncStates.first?.garminDisplayName ?? "Connecté") : "Non connecté")
                        .foregroundStyle(Color.rc.textSecondary)
                }
                if let last = syncStates.first?.lastGarminSyncAt {
                    HStack {
                        Text("Dernière synchro")
                        Spacer()
                        Text(last.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_FR"))))
                            .foregroundStyle(Color.rc.textSecondary)
                    }
                }
                if sync.phase == .syncing {
                    HStack(spacing: Spacing.s) {
                        ProgressView()
                        Text(sync.progress ?? "Synchro…")
                            .foregroundStyle(Color.rc.textSecondary)
                    }
                }
                if let message = sync.message {
                    Text(message)
                        .foregroundStyle(Color.rc.danger)
                }
                if sync.isConnected {
                    Button("Synchroniser maintenant") {
                        Task { await sync.sync(background: false) }
                    }
                    .disabled(sync.phase == .syncing)
                    Button("Se déconnecter", role: .destructive) {
                        Task { await sync.logout() }
                    }
                } else {
                    Button("Se connecter à Garmin") { showGarminLogin = true }
                }
                NavigationLink("Diagnostic", value: AppRoute.garminDiagnostic)
            } header: {
                Text("Garmin")
            } footer: {
                Text("Accès non officiel : Garmin peut le bloquer ou restreindre le compte. Tes identifiants sont saisis sur la page de Garmin, l'app ne les voit jamais. Se déconnecter garde les sorties déjà importées.")
            }

            Section {
                Button("Refaire la configuration") {
                    showOnboarding = true
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                        .foregroundStyle(Color.rc.textSecondary)
                }
            } header: {
                Text("À propos")
            } footer: {
                Text("Cette app ne remplace pas un avis médical. En cas de douleur ou de doute, consulte.")
            }
        }
        .scrollContentBackground(.hidden)
        .rcScreenBackground()
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingFlow(onFinish: { showOnboarding = false })
        }
        .fullScreenCover(isPresented: $showGarminLogin) { GarminLoginView() }
    }

    private func row(_ title: String, icon: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .lineLimit(1)
                .foregroundStyle(Color.rc.textSecondary)
        }
    }

    private var goalSummary: String {
        guard let goal = goals.first(where: { $0.isActive }) else { return "Aucun" }
        return goal.name + (goal.targetTimeS.map { " · " + Fmt.duration($0) } ?? "")
    }

    private var trainingSummary: String {
        guard let profile = profiles.first else { return "" }
        let count = profile.availableWeekdays.count
        return "\(count) jour\(count > 1 ? "s" : "") par semaine"
    }
}

/// Journal de la connexion et des synchros, pour diagnostiquer sans débogueur (ARCHITECTURE.md §9.5).
/// Hôtes, chemins et codes HTTP seulement : jamais de ticket, de jeton ni de paramètre de requête.
struct GarminDiagnosticView: View {
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        List {
            if sync.diagnostics.isEmpty {
                Text("Rien depuis l'ouverture de l'app.")
                    .foregroundStyle(Color.rc.textSecondary)
            }
            ForEach(Array(sync.diagnostics.enumerated().reversed()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .scrollContentBackground(.hidden)
        .rcScreenBackground()
        .navigationTitle("Diagnostic")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Réglages → Toi : ce qui sert au calcul des allures et des zones (sortie de référence, FC) et le profil.
struct ProfileEditView: View {
    @Query private var profiles: [AthleteProfile]

    var body: some View {
        Form {
            if let profile = profiles.first {
                ProfileFields(profile: profile)
            }
        }
        .scrollContentBackground(.hidden)
        .rcScreenBackground()
        .navigationTitle("Toi")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileFields: View {
    @Bindable var profile: AthleteProfile

    var body: some View {
        Section("Toi") {
            TextField("Prénom", text: $profile.firstName)
            DatePicker("Date de naissance", selection: $profile.birthDate, in: ...Date(), displayedComponents: .date)
            Picker("Sexe", selection: Binding(get: { profile.sex ?? "" }, set: { profile.sex = $0.isEmpty ? nil : $0 })) {
                Text("Non précisé").tag("")
                Text("Homme").tag("male")
                Text("Femme").tag("female")
            }
            DatePicker("Je cours depuis", selection: $profile.runningSince, in: ...Date(), displayedComponents: .date)
        }
        Section {
            Stepper(Fmt.decimal(profile.recentRunDistanceM / 1000, decimals: 1) + " km",
                    value: Binding(get: { profile.recentRunDistanceM / 1000 }, set: { profile.recentRunDistanceM = $0 * 1000 }),
                    in: 1...42.2, step: 0.5)
            Stepper("En " + Fmt.duration(profile.recentRunDurationS),
                    value: Binding(get: { profile.recentRunDurationS / 60 }, set: { profile.recentRunDurationS = $0 * 60 }),
                    in: 5...360, step: 1)
            Picker("Ressenti", selection: $profile.recentRunEffort) {
                Text("Facile").tag("easy")
                Text("Modéré").tag("moderate")
                Text("Dur").tag("hard")
            }
        } header: {
            Text("Sortie de référence")
        } footer: {
            Text("Utilisée tant que tes sorties Garmin des 6 dernières semaines ne suffisent pas pour estimer tes allures.")
        }
        Section {
            Toggle("Je connais ma FC max", isOn: Binding(get: { profile.hrMax != nil }, set: { profile.hrMax = $0 ? (profile.hrMax ?? 190) : nil }))
            if let hrMax = profile.hrMax {
                Stepper("FC max : \(hrMax) bpm", value: Binding(get: { hrMax }, set: { profile.hrMax = $0 }), in: 140...225)
            }
            Toggle("Je connais ma FC au repos", isOn: Binding(get: { profile.hrRest != nil }, set: { profile.hrRest = $0 ? (profile.hrRest ?? 60) : nil }))
            if let hrRest = profile.hrRest {
                Stepper("FC au repos : \(hrRest) bpm", value: Binding(get: { hrRest }, set: { profile.hrRest = $0 }), in: 35...100)
            }
            Toggle("Fixer mon allure seuil", isOn: Binding(get: { profile.thresholdPaceOverrideSPerKm != nil },
                                                        set: { profile.thresholdPaceOverrideSPerKm = $0 ? (profile.thresholdPaceOverrideSPerKm ?? 360) : nil }))
            if let threshold = profile.thresholdPaceOverrideSPerKm {
                Stepper("Allure seuil : " + Fmt.pace(sPerKm: threshold) + " /km",
                        value: Binding(get: { threshold }, set: { profile.thresholdPaceOverrideSPerKm = $0 }), in: 180...600, step: 5)
            }
        } header: {
            Text("Cœur et allures")
        } footer: {
            Text("Sans valeur saisie, la FC max est estimée par l'âge et l'allure seuil par tes sorties. Ne fixe l'allure seuil que si tu la connais par un test.")
        }
    }
}

/// Sélection des jours de la semaine (1 = lundi … 7 = dimanche).
struct WeekdayPicker: View {
    @Binding var selection: [Int]

    static let names = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
    private static let letters = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(1...7, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn {
                        selection.removeAll { $0 == day }
                    } else {
                        selection = (selection + [day]).sorted()
                    }
                } label: {
                    Text(WeekdayPicker.letters[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? Color.rc.onAccent : Color.rc.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? Color.rc.accent : Color.rc.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(WeekdayPicker.names[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
