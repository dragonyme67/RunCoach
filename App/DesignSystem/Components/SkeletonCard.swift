import SwiftUI

/// Carte « squelette » pendant un chargement : la forme du contenu, qui pulse doucement (étape 7, n° 10).
struct SkeletonCard: View {
    var lines = 3
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            bar(width: 0.4, height: 14)
            ForEach(0..<lines, id: \.self) { i in
                bar(width: i == lines - 1 ? 0.6 : 1, height: 12)
            }
        }
        .rcCard()
        .opacity(dim ? 0.45 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Chargement")
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(Color.rc.surfaceRaised)
                .frame(width: geo.size.width * width)
        }
        .frame(height: height)
    }
}
