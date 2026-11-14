import SwiftUI

/// Transition « zoom » d'iOS 18 : la carte touchée s'agrandit jusqu'à devenir l'écran de détail (étape 7, n° 10).
/// L'espace de noms vient de `MainTabs` ; sans lui (captures de la CI), navigation normale.
private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

private struct ZoomSource<ID: Hashable>: ViewModifier {
    let id: ID
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct ZoomDestination<ID: Hashable>: ViewModifier {
    let id: ID
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    /// Point de départ du zoom : la carte ou la ligne touchée.
    func zoomSource(_ id: some Hashable) -> some View { modifier(ZoomSource(id: id)) }
    /// Écran d'arrivée du zoom, même identifiant que la source.
    func zoomDestination(_ id: some Hashable) -> some View { modifier(ZoomDestination(id: id)) }
}
