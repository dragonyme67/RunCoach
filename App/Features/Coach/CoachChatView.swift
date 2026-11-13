import SwiftUI
import SwiftData

/// Conversation avec le coach. Information principale : la conversation.
/// Le coach répond à partir du bilan de forme, des séances des 14 prochains jours et de la conversation (§6.5).
/// Les modifications du plan qu'il propose s'appliquent seulement après « Appliquer » (`ConfirmCard`, §6.6).
struct CoachChatView: View {
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    @Environment(CoachService.self) private var coach
    @State private var draft = ""
    @FocusState private var isTyping: Bool

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
                    VStack(spacing: Spacing.m) {
                        EmptyState(icon: "key.fill", title: "Ajoute une clé IA gratuite",
                                   message: "Le coach répond avec ta propre clé Groq ou Gemini.")
                        NavigationLink(value: AppRoute.ai) {
                            Text("Ajouter ma clé")
                                .font(.headline)
                                .foregroundStyle(Color.rc.onAccent)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.rc.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .rcCard()
                }
                ForEach(messages) { message in
                    ChatBubble(text: message.text, isUser: message.role == "user")
                    if message.actionsState != "none" {
                        ConfirmCard(
                            lines: message.actionLines,
                            state: message.actionsState,
                            onApply: { coach.applyActions(of: message) },
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
        // Le clavier cachait la barre d'onglets sans pouvoir être fermé (constat sur l'iPhone).
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { isTyping = false }
        .rcScreenBackground()
        .navigationTitle("Coach")
        .safeAreaInset(edge: .bottom) {
            composer
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
                    .focused($isTyping)
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
