import SwiftUI
import MapKit

/// Carte du replay, plan B de l'étape 3 (ARCHITECTURE.md §8) : `MKMapView` piloté directement.
/// Avec la carte SwiftUI en relief, la caméra envoyée à chaque image n'était pas appliquée (constat sur l'iPhone,
/// 2026-11-13) : la carte restait figée pendant que le tracé dessiné par-dessus avançait.
/// Ici, à chaque image : la caméra est posée sur la carte, puis le tracé est projeté avec cette même caméra
/// et redessiné en coordonnées d'écran, au-dessus des arbres et bâtiments 3D.
struct ReplayMapView: UIViewRepresentable {
    /// Points du tracé (un tous les 12 m environ) et distance parcourue à chacun (m).
    let coordinates: [CLLocationCoordinate2D]
    let distances: [Double]
    let currentDistM: Double
    let runner: CLLocationCoordinate2D
    let heading: Double
    /// 0 = incliné en relief, 1 = satellite à plat, 2 = plan.
    let style: Int

    func makeUIView(context: Context) -> ReplayMapContainer { ReplayMapContainer() }

    func updateUIView(_ view: ReplayMapContainer, context: Context) { view.show(self) }
}

final class ReplayMapContainer: UIView {
    private let map = MKMapView()
    private let aheadHalo = CAShapeLayer(), ahead = CAShapeLayer()
    private let doneHalo = CAShapeLayer(), done = CAShapeLayer()
    private let dot = CAShapeLayer()
    private var current: ReplayMapView?
    private var style = -1

    /// Partie du tracé projetée à chaque image, derrière et devant le coureur : borne le nombre de points.
    private let behindM = 600.0
    private let aheadM = 1500.0

    init() {
        super.init(frame: .zero)
        // Carte non manipulable : un geste décalerait la caméra du coureur.
        map.isUserInteractionEnabled = false
        map.showsCompass = false
        map.showsScale = false
        addSubview(map)
        let accent = UIColor(Color.rc.accent).cgColor
        for (layer, color, width) in [(aheadHalo, UIColor.black.withAlphaComponent(0.35).cgColor, 9.0),
                                      (ahead, UIColor.white.withAlphaComponent(0.7).cgColor, 5.0),
                                      (doneHalo, UIColor.black.withAlphaComponent(0.35).cgColor, 9.0),
                                      (done, accent, 5.0)] {
            layer.strokeColor = color
            layer.fillColor = nil
            layer.lineWidth = width
            layer.lineCap = .round
            layer.lineJoin = .round
            self.layer.addSublayer(layer)
        }
        dot.fillColor = accent
        dot.strokeColor = UIColor.white.cgColor
        dot.lineWidth = 4
        dot.path = UIBezierPath(ovalIn: CGRect(x: -13, y: -13, width: 26, height: 26)).cgPath
        layer.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    override func layoutSubviews() {
        super.layoutSubviews()
        map.frame = bounds
        if let current { show(current) }
    }

    func show(_ state: ReplayMapView) {
        current = state
        if state.style != style {
            style = state.style
            map.preferredConfiguration = Self.configuration(style)
        }
        let tilted = state.style == 0
        // Sans animation : la caméra est appliquée tout de suite, la projection ci-dessous l'utilise.
        map.setCamera(MKMapCamera(lookingAtCenter: state.runner, fromDistance: tilted ? 500 : 600,
                                  pitch: tilted ? 60 : 0, heading: state.heading), animated: false)
        guard bounds.width > 0 else { return }

        let doneLine = UIBezierPath(), aheadLine = UIBezierPath()
        let runnerPoint = map.convert(state.runner, toPointTo: self)
        aheadLine.move(to: runnerPoint)
        var doneStarted = false
        for i in state.coordinates.indices {
            let d = state.distances[i]
            guard d > state.currentDistM - behindM, d < state.currentDistM + aheadM else { continue }
            let point = map.convert(state.coordinates[i], toPointTo: self)
            if d <= state.currentDistM {
                if doneStarted { doneLine.addLine(to: point) } else { doneLine.move(to: point); doneStarted = true }
            } else {
                aheadLine.addLine(to: point)
            }
        }
        if doneStarted { doneLine.addLine(to: runnerPoint) }

        // Pas d'animation implicite des calques : le tracé suit la carte image par image.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        aheadHalo.path = aheadLine.cgPath
        ahead.path = aheadLine.cgPath
        doneHalo.path = doneLine.cgPath
        done.path = doneLine.cgPath
        dot.position = runnerPoint
        CATransaction.commit()
    }

    private static func configuration(_ style: Int) -> MKMapConfiguration {
        switch style {
        case 0:
            let configuration = MKHybridMapConfiguration(elevationStyle: .realistic)
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        case 1:
            return MKImageryMapConfiguration(elevationStyle: .flat)
        default:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        }
    }
}
