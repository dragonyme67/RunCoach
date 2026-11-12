import SwiftUI

/// Bouton principal : plein accent, largeur complète.
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                if let icon = icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(Color.rc.onAccent)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.rc.accent, in: RoundedRectangle(cornerRadius: Radius.inner + 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Titre de section avec lien optionnel à droite.
struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.rcHeadline)
                .foregroundStyle(Color.rc.textPrimary)
            Spacer()
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.rc.accentText)
            }
        }
    }
}

/// Pastille d'état de synchro.
struct SyncPill: View {
    enum Status {
        case upToDate, syncing, offline, error
    }

    let state: Status

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 6)
        .background(Color.rc.surface, in: Capsule())
    }

    private var icon: String {
        switch state {
        case .upToDate: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var text: String {
        switch state {
        case .upToDate: return "À jour"
        case .syncing: return "Synchro…"
        case .offline: return "Hors ligne"
        case .error: return "Erreur"
        }
    }

    private var color: Color {
        switch state {
        case .upToDate: return Color.rc.accentText
        case .syncing, .offline: return Color.rc.textSecondary
        case .error: return Color.rc.danger
        }
    }
}

/// État vide d'un écran.
struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: icon)
                .font(.system(.largeTitle))
                .foregroundStyle(Color.rc.textSecondary)
            Text(title)
                .font(.rcTitle)
                .foregroundStyle(Color.rc.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.rc.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle = actionTitle, let action = action {
                PrimaryButton(title: actionTitle, action: action)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Bulle de conversation : utilisateur (accent) ou coach (surface).
struct ChatBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: Spacing.xxl) }
            Text(text)
                .font(.body)
                .foregroundStyle(isUser ? Color.rc.onAccent : Color.rc.textPrimary)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.m)
                .background(
                    isUser ? Color.rc.accent : Color.rc.surface,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            if !isUser { Spacer(minLength: Spacing.xxl) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((isUser ? "Toi : " : "Coach : ") + text)
    }
}

/// Proposition de changement de plan, à confirmer.
struct ConfirmCard: View {
    let lines: [String]
    let state: String
    let onApply: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label("Changement proposé", systemImage: "arrow.triangle.swap")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.rc.textPrimary)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(Color.rc.textSecondary)
            }
            if state == "proposed" {
                HStack(spacing: Spacing.m) {
                    Button("Ignorer", action: onIgnore)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.rc.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.rc.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    Button("Appliquer", action: onApply)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.rc.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.rc.accent, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Text(state == "applied" ? "Appliqué" : "Ignoré")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state == "applied" ? Color.rc.accentText : Color.rc.textSecondary)
            }
        }
        .rcCard()
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.rc.separator, lineWidth: 1)
        }
    }
}
