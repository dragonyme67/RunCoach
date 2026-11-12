import SwiftUI
import RunCoachCore

struct WelcomePage: View {
    var body: some View {
        OnboardingPage(
            icon: "figure.run",
            title: "RunCoach",
            subtitle: "Ton coach de course à pied : un plan qui s'adapte à toi, tes séances sur ta montre, tes sorties rejouées en 3D."
        ) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Label("Quelques questions pour te connaître", systemImage: "person.fill.questionmark")
                Label("Tout reste modifiable ensuite", systemImage: "slider.horizontal.3")
                Label("Tes données restent sur ton iPhone", systemImage: "lock.fill")
            }
            .font(.subheadline)
            .foregroundStyle(Color.rc.textPrimary)
            .rcCard()
        }
    }
}

struct AboutYouPage: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        OnboardingPage(icon: "person.fill", title: "Toi", subtitle: "Ton âge sert à estimer tes zones cardiaques.") {
            FieldCard(label: "Prénom") {
                TextField("Ton prénom", text: $draft.firstName)
                    .font(.title3)
                    .textContentType(.givenName)
            }
            FieldCard(label: "Date de naissance") {
                DatePicker("Date de naissance", selection: $draft.birthDate, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }
}

struct LevelPage: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        OnboardingPage(icon: "chart.bar.fill", title: "Ton niveau", subtitle: "Une sortie récente suffit pour calibrer tes allures.") {
            FieldCard(label: "Tu cours depuis") {
                Stepper("\(draft.runningMonths) mois", value: $draft.runningMonths, in: 0...240)
            }
            FieldCard(label: "Séances par semaine") {
                Stepper("\(draft.runsPerWeek) séances", value: $draft.runsPerWeek, in: 0...7)
            }
            FieldCard(label: "Une sortie récente") {
                Stepper(Fmt.decimal(draft.recentKm, decimals: 1) + " km", value: $draft.recentKm, in: 1...42, step: 0.5)
                Stepper("\(draft.recentMinutes) min", value: $draft.recentMinutes, in: 5...300)
                Text("Soit " + Fmt.pace(sPerKm: Double(draft.recentMinutes * 60) / draft.recentKm) + " /km")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.rc.accentText)
            }
            FieldCard(label: "Ressenti de cette sortie") {
                ChoiceRow(
                    options: [("easy", "Facile"), ("moderate", "Modéré"), ("hard", "Dur")],
                    selection: $draft.recentEffort
                )
            }
        }
    }
}

struct GoalPage: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        OnboardingPage(icon: "flag.checkered", title: "Ton objectif", subtitle: "Une course donne une date au plan. Sinon, on progresse sans échéance.") {
            FieldCard(label: "Objectif") {
                Toggle("Je prépare une course", isOn: $draft.hasRace)
            }
            if draft.hasRace {
                FieldCard(label: "Distance") {
                    Picker("Distance", selection: $draft.raceDistance) {
                        Text("5 km").tag(5.0)
                        Text("10 km").tag(10.0)
                        Text("Semi").tag(21.1)
                        Text("Marathon").tag(42.2)
                    }
                    .pickerStyle(.segmented)
                }
                FieldCard(label: "Date de la course") {
                    DatePicker("Date de la course", selection: $draft.raceDate, in: Date()..., displayedComponents: .date)
                        .labelsHidden()
                }
                FieldCard(label: "Temps visé") {
                    Stepper("\(draft.targetHours) h", value: $draft.targetHours, in: 0...6)
                    Stepper("\(draft.targetMinutes) min", value: $draft.targetMinutes, in: 0...59, step: 5)
                }
            }
        }
    }
}

struct AvailabilityPage: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        OnboardingPage(icon: "calendar", title: "Tes disponibilités", subtitle: "Le coach ne placera des séances que ces jours-là.") {
            FieldCard(label: "Jours où tu peux courir") {
                WeekdayPicker(selection: $draft.weekdays)
            }
            FieldCard(label: "Jour de la sortie longue") {
                Picker("Jour de la sortie longue", selection: $draft.longRunWeekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(WeekdayPicker.names[day - 1]).tag(day)
                    }
                }
                .labelsHidden()
            }
            FieldCard(label: "Durée maximale d'une séance") {
                Stepper("\(draft.maxSessionMinutes) min", value: $draft.maxSessionMinutes, in: 20...180, step: 5)
            }
        }
    }
}

struct HealthPage: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        OnboardingPage(icon: "cross.case.fill", title: "Ta santé", subtitle: "Pour adapter la charge et rester prudent.") {
            FieldCard(label: "Blessures ou antécédents (facultatif)") {
                TextField("Ex. : tendinite au genou droit en 2025", text: $draft.injuryNote, axis: .vertical)
                    .lineLimit(2...5)
            }
            FieldCard(label: "En ce moment") {
                Toggle("J'ai une douleur", isOn: $draft.currentPain)
            }
            FieldCard(label: "À lire") {
                Text("Cette app ne remplace pas un avis médical. En cas de douleur, de malaise ou de doute, arrête la séance et consulte un médecin.")
                    .font(.subheadline)
                    .foregroundStyle(Color.rc.textPrimary)
                Toggle("J'ai compris", isOn: $draft.disclaimerAccepted)
                    .tint(Color.rc.accent)
            }
        }
    }
}

struct StrengthPage: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        OnboardingPage(icon: "dumbbell.fill", title: "Renforcement", subtitle: "Fessiers, mollets, gainage : ce qui protège des blessures quand le volume monte.") {
            FieldCard(label: "Séances de renfo") {
                Toggle("Inclure du renfo dans mon plan", isOn: $draft.wantsStrength)
            }
            if draft.wantsStrength {
                FieldCard(label: "Matériel") {
                    ChoiceRow(
                        options: [("none", "Aucun"), ("dumbbells", "Haltères"), ("gym", "Salle")],
                        selection: $draft.equipment
                    )
                }
            }
        }
    }
}

struct GarminPage: View {
    var body: some View {
        OnboardingPage(icon: "applewatch", title: "Garmin", subtitle: "Connecte ton compte pour importer tes sorties et recevoir tes séances sur ta montre.") {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Label("Import automatique de tes sorties", systemImage: "arrow.down.circle.fill")
                Label("Séances envoyées sur ta montre", systemImage: "applewatch.radiowaves.left.and.right")
                Text("Cet accès n'est pas officiel : Garmin peut le bloquer ou restreindre le compte.")
                    .font(.caption)
                    .foregroundStyle(Color.rc.textSecondary)
            }
            .font(.subheadline)
            .foregroundStyle(Color.rc.textPrimary)
            .rcCard()
            Text("Disponible à l'étape 2.")
                .font(.caption)
                .foregroundStyle(Color.rc.textSecondary)
        }
    }
}

struct AIPage: View {
    var body: some View {
        OnboardingPage(icon: "sparkles", title: "Coach IA", subtitle: "Le coach utilise une IA gratuite, avec ta propre clé.") {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Label("Il explique chaque séance", systemImage: "text.bubble.fill")
                Label("Tu lui parles normalement pour changer ton plan", systemImage: "bubble.left.and.bubble.right.fill")
                Label("Il ne reçoit que des résumés chiffrés, jamais ta position", systemImage: "lock.fill")
            }
            .font(.subheadline)
            .foregroundStyle(Color.rc.textPrimary)
            .rcCard()
            Text("Disponible à l'étape 4. En attendant, le plan est généré sans IA.")
                .font(.caption)
                .foregroundStyle(Color.rc.textSecondary)
        }
    }
}

struct ReadyPage: View {
    let draft: OnboardingDraft

    var body: some View {
        OnboardingPage(
            icon: "checkmark.seal.fill",
            title: draft.firstName.isEmpty ? "C'est prêt" : "C'est prêt, \(draft.firstName)",
            subtitle: "Ton plan démarre doucement et progresse semaine après semaine."
        ) {
            VStack(spacing: Spacing.m) {
                StatTile(label: "Séances par semaine", value: "\(draft.weekdays.count)", icon: "calendar")
                if draft.hasRace {
                    StatTile(
                        label: "Objectif",
                        value: "\(draft.targetHours):" + (draft.targetMinutes < 10 ? "0" : "") + "\(draft.targetMinutes)",
                        unit: "sur " + Fmt.decimal(draft.raceDistance, decimals: 1) + " km",
                        icon: "flag.checkered"
                    )
                }
            }
        }
    }
}
