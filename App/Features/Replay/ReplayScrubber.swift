import SwiftUI

/// Barre de progression du replay : le profil d'altitude de la sortie, partie parcourue en couleur d'accent.
/// On y glisse le doigt pour se déplacer (étape 3.4, demande de l'utilisateur du 2026-11-14).
struct ReplayScrubber: View {
    /// Altitudes régulièrement espacées le long de la sortie.
    let profile: [Double]
    @Binding var progress: Double

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let lo = profile.min() ?? 0
                let span = max(1, (profile.max() ?? 0) - lo)
                var area = Path()
                area.move(to: CGPoint(x: 0, y: size.height))
                for (i, value) in profile.enumerated() {
                    let x = size.width * CGFloat(i) / CGFloat(profile.count - 1)
                    // Le relief garde au moins un quart de la hauteur : une sortie plate reste lisible.
                    let y = size.height * (1 - 0.25 - 0.75 * CGFloat((value - lo) / span))
                    area.addLine(to: CGPoint(x: x, y: y))
                }
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(Color.white.opacity(0.22)))
                let doneWidth = size.width * CGFloat(progress)
                context.clip(to: Path(CGRect(x: 0, y: 0, width: doneWidth, height: size.height)))
                context.fill(area, with: .color(Color.rc.accent.opacity(0.9)))
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.white)
                    .frame(width: 4)
                    .shadow(radius: 2)
                    .offset(x: geo.size.width * CGFloat(progress) - 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                progress = max(0, min(1, value.location.x / max(1, geo.size.width)))
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Position dans la sortie")
        .accessibilityValue("\(Int((progress * 100).rounded())) %")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: progress = min(1, progress + 0.05)
            case .decrement: progress = max(0, progress - 0.05)
            @unknown default: break
            }
        }
    }
}
