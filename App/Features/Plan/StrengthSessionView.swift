import SwiftUI
import RunCoachCore

/// Renfo guidé (étape 7, n° 4) : une série à la fois, minuteur pour le gainage et les repos, retour haptique.
/// L'écran reste allumé pendant la séance. Rien n'est enregistré : la montre, elle, enregistre l'activité.
struct StrengthSessionView: View {
    let exercises: [StrengthExercise]
    @Environment(\.dismiss) private var dismiss
    @State private var phases: [StrengthSession.Phase] = []
    @State private var index = 0
    /// Secondes restantes du minuteur en cours (gainage ou repos).
    @State private var remaining: Double = 0
    @State private var running = false
    @State private var confirmQuit = false

    private var phase: StrengthSession.Phase? { phases.indices.contains(index) ? phases[index] : nil }
    private var finished: Bool { !phases.isEmpty && index >= phases.count }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            topBar
            Spacer()
            if finished {
                finishedView
            } else if let phase {
                phaseView(phase)
            }
            Spacer()
            if let next = nextWork, !finished {
                Text("Ensuite : \(StrengthNames.name(next.exerciseId))")
                    .font(.subheadline)
                    .foregroundStyle(Color.rc.textSecondary)
            }
        }
        .padding(Spacing.l)
        .rcScreenBackground()
        .onAppear {
            phases = StrengthSession.phases(exercises)
            start(at: 0)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // Relancé à chaque phase et à chaque pause : un gainage suivi d'un repos garde `running` vrai.
        .task(id: "\(index)-\(running)") { await tick() }
        .sensoryFeedback(.success, trigger: index)
        .sensoryFeedback(.impact(weight: .light), trigger: Int(remaining.rounded(.up))) { _, new in running && new > 0 && new <= 3 }
        .confirmationDialog("Arrêter la séance ?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Arrêter", role: .destructive) { dismiss() }
            Button("Continuer", role: .cancel) {}
        }
    }

    // MARK: - Écrans

    private var topBar: some View {
        HStack {
            Button {
                if finished { dismiss() } else { confirmQuit = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Fermer")
            ProgressView(value: Double(min(index, phases.count)), total: Double(max(1, phases.count)))
                .tint(Color.rc.accent)
        }
    }

    @ViewBuilder
    private func phaseView(_ phase: StrengthSession.Phase) -> some View {
        VStack(spacing: Spacing.l) {
            switch phase.kind {
            case .rest:
                Text("Repos")
                    .font(.rcTitle)
                    .foregroundStyle(Color.rc.textSecondary)
                countdown(total: restSeconds(phase))
                Button("Passer le repos") { advance() }
                    .font(.headline)
            case .reps(let reps):
                header(phase)
                Text("\(reps)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.rc.textPrimary)
                Text("répétitions")
                    .font(.headline)
                    .foregroundStyle(Color.rc.textSecondary)
                PrimaryButton(title: "Série faite", icon: "checkmark") { advance() }
            case .timed(let seconds):
                header(phase)
                countdown(total: Double(seconds))
                PrimaryButton(title: running ? "Pause" : (remaining < Double(seconds) ? "Reprendre" : "Démarrer"),
                              icon: running ? "pause.fill" : "play.fill") { running.toggle() }
            }
        }
    }

    private func header(_ phase: StrengthSession.Phase) -> some View {
        VStack(spacing: Spacing.s) {
            Text(StrengthNames.name(phase.exerciseId))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.rc.textPrimary)
            Text("Série \(phase.set) sur \(phase.sets)")
                .font(.headline)
                .foregroundStyle(Color.rc.accentText)
            if let note = phase.note {
                Text(note)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.rc.textSecondary)
            }
        }
    }

    private func countdown(total: Double) -> some View {
        ZStack {
            Circle().stroke(Color.rc.surfaceRaised, lineWidth: 14)
            Circle()
                .trim(from: 0, to: total > 0 ? remaining / total : 0)
                .stroke(Color.rc.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: remaining)
            Text(Fmt.duration(remaining.rounded(.up)))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.rc.textPrimary)
        }
        .frame(width: 220, height: 220)
        .accessibilityElement()
        .accessibilityLabel("Temps restant \(Int(remaining.rounded(.up))) secondes")
    }

    private var finishedView: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.rc.accent)
                .symbolEffect(.bounce, value: finished)
            Text("Séance terminée")
                .font(.rcTitle)
                .foregroundStyle(Color.rc.textPrimary)
            PrimaryButton(title: "Fermer") { dismiss() }
        }
    }

    // MARK: - Minuteur

    private var nextWork: StrengthSession.Phase? {
        phases.dropFirst(index + 1).first { if case .rest = $0.kind { return false } else { return true } }
    }

    private func restSeconds(_ phase: StrengthSession.Phase) -> Double {
        if case .rest(let s) = phase.kind { return Double(s) }
        return 0
    }

    /// Prépare la phase `i` : un repos démarre seul, un gainage attend « Démarrer ».
    private func start(at i: Int) {
        index = i
        guard let phase else { running = false; return }
        switch phase.kind {
        case .rest(let s):
            remaining = Double(s)
            running = true
        case .timed(let s):
            remaining = Double(s)
            running = false
        case .reps:
            remaining = 0
            running = false
        }
    }

    private func advance() { start(at: index + 1) }

    private func tick() async {
        while running, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard running else { return }
            remaining = max(0, remaining - 0.1)
            if remaining <= 0 {
                advance()
                return
            }
        }
    }
}
