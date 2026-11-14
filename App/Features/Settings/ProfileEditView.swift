import SwiftUI
import SwiftData
import RunCoachCore

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
