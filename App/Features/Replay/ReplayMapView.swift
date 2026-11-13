import SwiftUI
import MapKit
import RunCoachCore

/// Carte du replay, plan B de l'étape 3 (ARCHITECTURE.md §8) : `MKMapView` piloté directement.
/// Avec la carte SwiftUI en relief, la caméra envoyée à chaque image n'était pas appliquée (constat sur l'iPhone,
/// 2026-11-13) : la carte restait figée pendant que le tracé dessiné par-dessus avançait.
/// Ici, à chaque image : la caméra est posée sur la carte, puis le tracé est projeté avec cette même caméra
/// et redessiné en coordonnées d'écran, au-dessus de la carte.
struct ReplayMapView: UIViewRepresentable {
    /// Points du tracé (un tous les 12 m environ) et distance parcourue à chacun (m).
    let coordinates: [CLLocationCoordinate2D]
    let distances: [Double]
    let currentDistM: Double
    let runner: CLLocationCoordinate2D
    let camera: ReplayCamera
    /// 0 = satellite vu du dessus, 1 = relief 3D incliné, 2 = plan incliné sans relief.
    let style: Int
    /// Partie du tracé dessinée, derrière et devant le coureur (tout le tracé pendant l'entrée et la sortie).
    let behindM: Double
    let aheadM: Double
    /// Halo du coureur : couleur de sa zone cardiaque ; `pulse` de 0 à 1 dans le battement en cours.
    let haloColor: UIColor
    let pulse: Double

    func makeUIView(context: Context) -> ReplayMapContainer { ReplayMapContainer() }

    func updateUIView(_ view: ReplayMapContainer, context: Context) { view.show(self) }
}

final class ReplayMapContainer: UIView {
    private let map = MKMapView()
    private let aheadHalo = CAShapeLayer(), ahead = CAShapeLayer()
    private let doneHalo = CAShapeLayer(), done = CAShapeLayer()
    private let halo = CAShapeLayer(), dot = CAShapeLayer()
    private var current: ReplayMapView?
    private var style = -1

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
        let disc = UIBezierPath(ovalIn: CGRect(x: -13, y: -13, width: 26, height: 26)).cgPath
        halo.path = disc
        layer.addSublayer(halo)
        dot.fillColor = accent
        dot.strokeColor = UIColor.white.cgColor
        dot.lineWidth = 4
        dot.path = disc
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
        let cam = state.camera
        // Sans animation : la caméra est appliquée tout de suite, la projection ci-dessous l'utilise.
        map.setCamera(MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: cam.centerLat, longitude: cam.centerLon),
                                  fromDistance: cam.distanceM, pitch: cam.pitchDeg, heading: cam.headingDeg),
                      animated: false)
        guard bounds.width > 0 else { return }

        let doneLine = UIBezierPath(), aheadLine = UIBezierPath()
        let runnerPoint = map.convert(state.runner, toPointTo: self)
        aheadLine.move(to: runnerPoint)
        var donePenDown = false, aheadPenDown = true
        for i in state.coordinates.indices {
            let d = state.distances[i]
            guard d > state.currentDistM - state.behindM, d < state.currentDistM + state.aheadM else { continue }
            let isDone = d <= state.currentDistM
            let c = state.coordinates[i]
            // Un point derrière la caméra inclinée est projeté n'importe où : il coupe le trait au lieu d'y entrer.
            guard ReplayDirector.isInFrontOfCamera(lat: c.latitude, lon: c.longitude,
                                                   centerLat: cam.centerLat, centerLon: cam.centerLon,
                                                   headingDeg: cam.headingDeg, cameraDistanceM: cam.distanceM,
                                                   pitchDeg: cam.pitchDeg) else {
                if isDone { donePenDown = false } else { aheadPenDown = false }
                continue
            }
            let point = map.convert(c, toPointTo: self)
            let line = isDone ? doneLine : aheadLine
            if isDone ? donePenDown : aheadPenDown { line.addLine(to: point) } else { line.move(to: point) }
            if isDone { donePenDown = true } else { aheadPenDown = true }
        }
        if donePenDown { doneLine.addLine(to: runnerPoint) }

        // Pas d'animation implicite des calques : le tracé suit la carte image par image.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        aheadHalo.path = aheadLine.cgPath
        ahead.path = aheadLine.cgPath
        doneHalo.path = doneLine.cgPath
        done.path = doneLine.cgPath
        dot.position = runnerPoint
        // Onde qui part du point et s'efface, une par battement.
        halo.position = runnerPoint
        halo.fillColor = state.haloColor.cgColor
        halo.opacity = Float(0.7 * (1 - state.pulse))
        halo.setAffineTransform(CGAffineTransform(scaleX: 1 + 1.4 * state.pulse, y: 1 + 1.4 * state.pulse))
        CATransaction.commit()
    }

    /// Sans relief : aucun arbre ni bâtiment 3D, donc un trait dessiné au-dessus reste exactement sur le sol.
    /// Avec le relief, le trait (au sol) glisse sur les objets 3D quand la caméra bouge (constat sur l'iPhone).
    /// Le satellite sans relief ignore l'inclinaison (capture de la CI, MapKit, 2026-11-13).
    private static func configuration(_ style: Int) -> MKMapConfiguration {
        switch style {
        case 0:
            let configuration = MKHybridMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        case 1:
            let configuration = MKHybridMapConfiguration(elevationStyle: .realistic)
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        default:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        }
    }
}
