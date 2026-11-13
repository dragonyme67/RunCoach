import SwiftUI
import SwiftData

/// Conversation avec le coach. Information principale : la conversation.
/// Le coach répond à partir du bilan de forme, des séances des 14 prochains jours et de la conversation (§6.5).
/// shortcut: le chat ne modifie pas encore le plan (actions et `ConfirmCard`, §6.6) ; à ajouter avec l'étape 4.7.
struct CoachChatView: View {
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    @Environment(CoachService.self) private var coach
    @State private var draft = ""
    @State private var showSettings = false

    private let suggestions = [
        "Comment se passe ma séance de demain ?",
        "Fais-moi un bilan de ma forme",
        "Quels sont mes points faibles ?",
        "Je suis très fatigué",
        "J'ai mal au genou"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if !coach.hasKey {
                    EmptyState(icon: "key.fill", title: "Ajoute une clé IA gratuite",
                               message: "Le coach répond avec ta propre clé Groq ou Gemini, à saisir dans Réglages.",
                               actionTitle: "Ouvrir les réglages") { showSettings = true }
                        .rcCard()
                }
                ForEach(messages) { message in
                    ChatBubble(text: message.text, isUser: message.role == "user")
                    if message.actionsState != "none" {
                        ConfirmCard(
                            lines: message.actionLines,
                            state: message.actionsState,
                            onApply: { message.actionsState = "applied" },
                            onIgnore: { message.actionsState = "rejected" }
                        )
                    }
                }
                if coach.isReplying {
                    HStack(spacing: Spacing.s) {
                        ProgressView()
                        Text("Le coach réfléchit…")
                            .font(.subheadline)
                            .foregroundStyle(Color.rc.textSecondary)
                    }
                }
                if let error = coach.chatError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.rc.danger)
                }
            }
            .padding(Spacing.l)
        }
        .defaultScrollAnchor(.bottom)
        .rcScreenBackground()
        .navigationTitle("Coach")
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { AISettingsView() }
        }
    }

    private var composer: some View {
        VStack(spacing: Spacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            draft = suggestion
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.rc.textPrimary)
                        .padding(.horizontal, Spacing.m)
                        .frame(minHeight: 36)
                        .background(Color.rc.surface, in: Capsule())
                    }
                }
                .padding(.horizontal, Spacing.l)
            }
            HStack(spacing: Spacing.s) {
                TextField("Écris à ton coach…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.m)
                    .background(Color.rc.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Button {
                    let text = draft
                    draft = ""
                    Task { await coach.send(text) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(Color.rc.onAccent)
                        .frame(width: 44, height: 44)
                        .background(Color.rc.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coach.isReplying)
                .accessibilityLabel("Envoyer")
            }
            .padding(.horizontal, Spacing.l)
        }
        .padding(.vertical, Spacing.s)
        .background(Color.rc.background)
    }
}
