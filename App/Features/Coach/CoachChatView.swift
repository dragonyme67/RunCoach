import SwiftUI
import SwiftData

/// Conversation avec le coach. Information principale : la conversation.
// shortcut: étape 1 = conversation factice, l'envoi ajoute le message sans réponse ; l'IA arrive à l'étape 4.
struct CoachChatView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    @State private var draft = ""

    private let suggestions = [
        "Je suis fatigué aujourd'hui",
        "Déplace ma séance de demain",
        "Explique-moi ma semaine",
        "Ajoute du renfo"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
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
            }
            .padding(Spacing.l)
        }
        .defaultScrollAnchor(.bottom)
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
                    .lineLimit(1...4)
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.m)
                    .background(Color.rc.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(Color.rc.onAccent)
                        .frame(width: 44, height: 44)
                        .background(Color.rc.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Envoyer")
            }
            .padding(.horizontal, Spacing.l)
        }
        .padding(.vertical, Spacing.s)
        .background(Color.rc.background)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        context.insert(ChatMessage(role: "user", text: text))
        draft = ""
    }
}
