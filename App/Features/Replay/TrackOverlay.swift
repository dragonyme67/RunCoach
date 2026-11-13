import SwiftUI
import MapKit

/// Prototype 3.0 (ARCHITECTURE.md §8, étape 3) : tracé et coureur dessinés en coordonnées d'écran par-dessus
/// la carte inclinée en relief. Posés sur la carte, les arbres et bâtiments 3D les masquaient ; dessinés
/// au-dessus, ils restent visibles. Chaque point est projeté par `MapProxy.convert`, qui suit la perspective.
/// Redessiné à chaque changement de caméra (`cameraTick`), pour rester calé sur la carte.
struct TrackOverlay: View {
    let proxy: MapProxy
    let coordinates: [CLLocationCoordinate2D]
    /// Distance parcourue (m) à chaque point de `coordinates`.
    let distances: [Double]
    let currentDistM: Double
    let runner: CLLocationCoordinate2D
    let cameraTick: Int

    /// Partie du tracé projetée à chaque image : derrière et devant le coureur. Borne le nombre de points.
    private let behindM = 600.0
    private let aheadM = 1500.0

    var body: some View {
        // Projection ici (fil principal, comme `MapProxy` l'exige) ; le Canvas ne fait que dessiner.
        _ = cameraTick
        let runnerPoint = proxy.convert(runner, to: .local)
        var done: [CGPoint?] = []
        var ahead: [CGPoint?] = [runnerPoint]
        for i in coordinates.indices where distances[i] > currentDistM - behindM && distances[i] < currentDistM + aheadM {
            let point = proxy.convert(coordinates[i], to: .local)
            if distances[i] <= currentDistM { done.append(point) } else { ahead.append(point) }
        }
        done.append(runnerPoint)

        return Canvas { context, _ in
            guard let runnerPoint else { return }
            let style = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            let halo = StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
            for (points, color) in [(ahead, Color.white.opacity(0.7)), (done, Color.rc.accent)] {
                let path = Self.path(points)
                // Liseré sombre : le trait reste lisible sur un satellite clair (route, béton).
                context.stroke(path, with: .color(.black.opacity(0.35)), style: halo)
                context.stroke(path, with: .color(color), style: style)
            }

            let dot = CGRect(x: runnerPoint.x - 13, y: runnerPoint.y - 13, width: 26, height: 26)
            context.fill(Path(ellipseIn: dot), with: .color(Color.rc.accent))
            context.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Ligne brisée ; un point non projetable (hors champ) coupe le trait.
    private static func path(_ points: [CGPoint?]) -> Path {
        var path = Path()
        var penDown = false
        for point in points {
            guard let point else { penDown = false; continue }
            if penDown { path.addLine(to: point) } else { path.move(to: point); penDown = true }
        }
        return path
    }
}
