import SwiftUI
import SwiftData
import RunCoachCore

/// Réglages (ouverts en feuille depuis l'avatar de l'écran Aujourd'hui).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [AthleteProfile]
    @Query private var goals: [Goal]
    @Query private var syncStates: [SyncState]
    @Environment(SyncEngine.self) private var sync
    @State private var showOnboarding = false
    @State private var showGarminLogin = false

    var body: some View {
        Form {
            Section("Profil") {
                if let profile = profiles.first {
                    NavigationLink {
                        ProfileEditView(profile: profile)
                    } label: {
                        Label(profile.firstName.isEmpty ? "Mon profil" : profile.firstName, systemImage: "person.fill")
                    }
                }
                if let goal = goals.first(where: { $0.isActive }) {
                    HStack {
                        Label(goal.name, systemImage: "flag.checkered")
                        Spacer()
                        if let target = goal.targetTimeS {
                            Text(Fmt.duration(target))
                                .monospacedDigit()
                                .foregroundStyle(Color.rc.textSecondary)
                        }
                    }
                }
                Button("Refaire la configuration") {
                    showOnboarding = true
                }
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
                NavigationLink("Diagnostic") { GarminDiagnosticView() }
            } header: {
                Text("Garmin")
            } footer: {
                Text("Accès non officiel : Garmin peut le bloquer ou restreindre le compte. Tes identifiants sont saisis sur la page de Garmin, l'app ne les voit jamais. Se déconnecter garde les sorties déjà importées.")
            }

            Section {
                HStack {
                    Label("Fournisseur", systemImage: "sparkles")
                    Spacer()
                    Text("Aucun")
                        .foregroundStyle(Color.rc.textSecondary)
                }
            } header: {
                Text("Coach IA")
            } footer: {
                Text("Le coach IA arrive à l'étape 4, avec ta propre clé gratuite. Seuls des résumés chiffrés lui sont envoyés, jamais ta position.")
            }

            Section {
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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingFlow(onFinish: { showOnboarding = false })
        }
        .fullScreenCover(isPresented: $showGarminLogin) { GarminLoginView() }
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

/// Édition du profil : les mêmes champs que l'onboarding.
struct ProfileEditView: View {
    @Bindable var profile: AthleteProfile

    var body: some View {
        Form {
            Section("Toi") {
                TextField("Prénom", text: $profile.firstName)
                DatePicker("Date de naissance", selection: $profile.birthDate, displayedComponents: .date)
            }
            Section("Disponibilités") {
                WeekdayPicker(selection: $profile.availableWeekdays)
                Picker("Sortie longue", selection: $profile.longRunWeekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(WeekdayPicker.names[day - 1]).tag(day)
                    }
                }
                Stepper("Durée max : \(profile.maxSessionMinutes) min", value: $profile.maxSessionMinutes, in: 20...180, step: 5)
            }
            Section {
                Toggle("Douleur en ce moment", isOn: $profile.currentPain)
                Picker("Fatigue", selection: $profile.fatigueLevel) {
                    Text("Faible").tag("low")
                    Text("Normale").tag("normal")
                    Text("Élevée").tag("high")
                }
                TextField("Blessures ou antécédents", text: $profile.injuryNote, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Santé")
            } footer: {
                Text("Une douleur déclarée allège immédiatement ton plan.")
            }
            Section("Renforcement") {
                Toggle("Inclure du renfo", isOn: $profile.wantsStrength)
                Picker("Matériel", selection: $profile.strengthEquipment) {
                    Text("Aucun").tag("none")
                    Text("Haltères").tag("dumbbells")
                    Text("Salle").tag("gym")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .rcScreenBackground()
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
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
