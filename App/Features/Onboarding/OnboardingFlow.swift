import SwiftUI

/// Réponses saisies pendant l'onboarding.
struct OnboardingDraft {
    var firstName = ""
    var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    var runningMonths = 1
    var runsPerWeek = 3
    var recentKm = 5.0
    var recentMinutes = 32
    var recentEffort = "moderate"
    var hasRace = true
    var raceDistance = 21.1
    var raceDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    var targetHours = 2
    var targetMinutes = 0
    var weekdays = [2, 4, 7]
    var longRunWeekday = 7
    var maxSessionMinutes = 60
    var injuryNote = ""
    var currentPain = false
    var disclaimerAccepted = false
    var wantsStrength = true
    var equipment = "none"
}

/// Premier lancement : une question par page, bouton Continuer en bas.
// shortcut: étape 1 = parcours visuel, les réponses ne sont pas enregistrées ;
// l'étape 2 branche Garmin, l'étape 4 la clé IA et la génération du plan.
struct OnboardingFlow: View {
    let onFinish: () -> Void
    @State private var step = 0
    @State private var draft = OnboardingDraft()

    private let lastStep = 9

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step + 1), total: Double(lastStep + 1))
                .tint(Color.rc.accent)
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.m)
                .accessibilityLabel("Étape \(step + 1) sur \(lastStep + 1)")
            ScrollView {
                page
                    .padding(Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: Spacing.s) {
                PrimaryButton(title: step == lastStep ? "C'est parti" : "Continuer") {
                    if step == lastStep {
                        onFinish()
                    } else {
                        withAnimation(.rcStandard) { step += 1 }
                    }
                }
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.4)
                if step > 0 {
                    Button("Retour") {
                        withAnimation(.rcStandard) { step -= 1 }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.rc.textSecondary)
                    .frame(minHeight: 44)
                }
            }
            .padding(Spacing.l)
        }
        .rcScreenBackground()
        .sensoryFeedback(.selection, trigger: step)
    }

    /// Seul l'avertissement médical est bloquant.
    private var canContinue: Bool {
        step != 5 || draft.disclaimerAccepted
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case 0: WelcomePage()
        case 1: AboutYouPage(draft: $draft)
        case 2: LevelPage(draft: $draft)
        case 3: GoalPage(draft: $draft)
        case 4: AvailabilityPage(draft: $draft)
        case 5: HealthPage(draft: $draft)
        case 6: StrengthPage(draft: $draft)
        case 7: GarminPage()
        case 8: AIPage()
        default: ReadyPage(draft: draft)
        }
    }
}

/// Gabarit d'une page : icône, titre, sous-titre, contenu.
struct OnboardingPage<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let content: Content

    init(icon: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Image(systemName: icon)
                .font(.system(.largeTitle))
                .foregroundStyle(Color.rc.accentText)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.rc.textPrimary)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(Color.rc.textSecondary)
            }
            content
        }
    }
}

/// Ligne de formulaire dans une carte.
struct FieldCard<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(label).rcLabel()
            content
        }
        .rcCard()
    }
}

/// Choix exclusif en grandes pastilles.
struct ChoiceRow: View {
    let options: [(value: String, label: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: Spacing.s) {
            ForEach(0..<options.count, id: \.self) { index in
                let option = options[index]
                let isOn = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? Color.rc.onAccent : Color.rc.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(isOn ? Color.rc.accent : Color.rc.surfaceRaised,
                                    in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
