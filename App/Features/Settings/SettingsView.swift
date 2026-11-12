import SwiftUI
import SwiftData
import RunCoachCore

/// Réglages (ouverts en feuille depuis l'avatar de l'écran Aujourd'hui).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [AthleteProfile]
    @Query private var goals: [Goal]
    @Query private var syncStates: [SyncState]
    @State private var showOnboarding = false

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
                    Text("Non connecté")
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
            } header: {
                Text("Garmin")
            } footer: {
                Text("La connexion à Garmin arrive à l'étape 2. Elle passe par un accès non officiel : Garmin peut le bloquer ou restreindre le compte.")
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
                HStack {
                    Text("Données")
                    Spacer()
                    Text("Factices (étape 1)")
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
