import SwiftUI
import MapKit
import Charts
import RunCoachCore

/// Replay d'une sortie : carte qui tourne avec le coureur (il avance toujours vers le haut de l'écran).
/// Par défaut, vue inclinée en relief ; le tracé est dessiné par-dessus la carte (`ReplayMapView`) :
/// posé sur la carte, il disparaissait sous les arbres et bâtiments 3D.
/// Fluidité : la lecture avance à vitesse constante sur la distance (marche et arrêts ne la ralentissent pas),
/// la position est interpolée à chaque image, et la caméra tourne en douceur vers un point situé devant.
struct ReplayView: View {
    let run: Run
    /// 0 = incliné en relief, 1 = satellite à plat, 2 = plan.
    @State var style = 0
    /// Position de lecture, fraction des relevés (0 = départ).
    @State var progress: Double = 0
    /// Cap de la caméra, lissé (`ReplayDirector.smoothHeading`).
    @State private var cameraHeading: Double = 0
    /// Indices des points dessinés en surimpression : un tous les 12 m environ.
    @State private var overlayIndices: [Int] = []
    @Environment(\.dismiss) private var dismiss
    @State private var track: Track?
    @State private var coordinates: [CLLocationCoordinate2D] = []
    @State private var isPlaying = false
    @State private var speed = 1
    @State private var metric = 0
    @State private var streetScene: MKLookAroundScene?
    @State private var showStreet = false
    @State private var noStreet = false
    @State private var chartPoints: [ChartPoint] = []

    private var index: Int {
        guard coordinates.count > 1 else { return 0 }
        return min(coordinates.count - 1, max(0, Int(progress * Double(coordinates.count - 1))))
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
            closeButton
        }
        .safeAreaInset(edge: .bottom) {
            panel
        }
        .background { clock }
        .task {
            guard track == nil else { return }
            let loaded = run.loadTrack()
            track = loaded
            coordinates = RouteMap.coordinates(loaded)
            overlayIndices = Self.overlayIndices(loaded?.dist ?? [], stepM: 12)
            chartPoints = makeChartPoints()
            cameraHeading = targetHeading
        }
        .onChange(of: progress) {
            // Barre déplacée à la main, lecture en pause : la caméra se tourne directement dans le bon sens.
            if !isPlaying { cameraHeading = targetHeading }
        }
        .onChange(of: metric) {
            chartPoints = makeChartPoints()
        }
        .lookAroundViewer(isPresented: $showStreet, initialScene: streetScene)
        .alert("Pas de vue de rue ici", isPresented: $noStreet) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Apple n'a des images qu'au bord des routes où ses voitures sont passées.")
        }
        .sensoryFeedback(.selection, trigger: speed)
        .sensoryFeedback(.selection, trigger: style)
    }

    /// Horloge de lecture, calée sur le rafraîchissement de l'écran.
    private var clock: some View {
        TimelineView(.animation(paused: !isPlaying)) { context in
            Color.clear.onChange(of: context.date) { old, new in
                // Borné : à la reprise après une pause, l'écart entre deux dates vaut toute la pause.
                let elapsedS = min(0.1, new.timeIntervalSince(old))
                guard let track, let start = track.dist.first, let end = track.dist.last, end > start else { return }
                let playS = ReplayDirector.playbackDurationS(runDurationS: track.t.last ?? run.durationS)
                let distanceM = min(end, currentDistM + elapsedS * Double(speed) * (end - start) / playS)
                progress = track.index(atDistanceM: distanceM) / Double(max(1, track.dist.count - 1))
                cameraHeading = ReplayDirector.smoothHeading(cameraHeading, toward: targetHeading, dt: elapsedS)
                if distanceM >= end { isPlaying = false }
            }
        }
    }

    /// Cap visé : la direction d'un point situé un peu plus loin sur le tracé.
    private var targetHeading: Double {
        track?.bearing(atDistanceM: currentDistM, aheadM: ReplayDirector.lookAheadM) ?? 0
    }

    @ViewBuilder
    private var map: some View {
        if let track, coordinates.count > 1 {
            let pose = track.pose(at: progress)
            ReplayMapView(coordinates: overlayIndices.map { coordinates[$0] },
                          distances: overlayIndices.map { track.dist[$0] },
                          currentDistM: currentDistM,
                          runner: CLLocationCoordinate2D(latitude: pose.lat, longitude: pose.lon),
                          heading: cameraHeading,
                          style: style)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        } else {
            Color.rc.background.ignoresSafeArea()
        }
    }

    /// Distance parcourue à la position de lecture, interpolée entre deux relevés comme `Track.pose(at:)`.
    private var currentDistM: Double {
        guard let dist = track?.dist, dist.count > 1 else { return 0 }
        let position = max(0, min(1, progress)) * Double(dist.count - 1)
        let i = min(dist.count - 2, Int(position))
        return dist[i] + (dist[i + 1] - dist[i]) * (position - Double(i))
    }

    /// Un indice tous les `stepM` mètres, plus le dernier : borne le nombre de points projetés par image.
    static func overlayIndices(_ dist: [Double], stepM: Double) -> [Int] {
        guard let first = dist.first else { return [] }
        var indices: [Int] = []
        var next = first
        for (i, d) in dist.enumerated() where d >= next {
            indices.append(i)
            next = d + stepM
        }
        if indices.last != dist.count - 1 { indices.append(dist.count - 1) }
        return indices
    }

    private var closeButton: some View {
        HStack(spacing: Spacing.s) {
            mapButton("xmark", label: "Fermer") {
                dismiss()
            }
            Spacer()
            mapButton("binoculars.fill", label: "Vue de la rue à cet endroit") {
                isPlaying = false
                Task { await openStreet() }
            }
            mapButton(["view.3d", "globe.europe.africa.fill", "map.fill"][style], label: "Style de carte") {
                style = (style + 1) % 3
            }
            .accessibilityValue(["Inclinée", "Satellite à plat", "Plan"][style])
        }
        .padding(.horizontal, Spacing.l)
    }

    private func mapButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(label)
    }

    /// Ouvre la vue de rue d'Apple (Look Around) au point courant, si Apple a des images à proximité.
    private func openStreet() async {
        guard coordinates.count > 1 else { return }
        streetScene = try? await MKLookAroundSceneRequest(coordinate: coordinates[index]).scene
        showStreet = streetScene != nil
        noStreet = streetScene == nil
    }

    private var panel: some View {
        VStack(spacing: Spacing.m) {
            stats
            chart
            controls
        }
        .padding(Spacing.l)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.horizontal, Spacing.s)
        .environment(\.colorScheme, .dark)
    }

    private var stats: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 3), spacing: Spacing.s) {
            ReplayStat(label: "Allure", value: Fmt.pace(speedMps: value(track?.speed)), unit: "/km")
            ReplayStat(label: "FC", value: number(track?.hr), unit: "bpm")
            ReplayStat(label: "Cadence", value: number(track?.cad), unit: "pas/min")
            ReplayStat(label: "Altitude", value: number(track?.ele), unit: "m")
            ReplayStat(label: "Distance", value: Fmt.km(value(track?.dist)), unit: "km")
            ReplayStat(label: "Temps", value: Fmt.duration(value(track?.t)), unit: "")
        }
    }

    private var chart: some View {
        VStack(spacing: Spacing.s) {
            Picker("Courbe", selection: $metric) {
                Text("Allure").tag(0)
                Text("FC").tag(1)
                Text("Altitude").tag(2)
            }
            .pickerStyle(.segmented)
            // Courbe figée et curseur dessiné par-dessus : la courbe n'est pas recalculée à chaque image.
            ReplayChart(points: chartPoints, xMax: Double(max(1, coordinates.count - 1)))
                .overlay {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 2)
                            .offset(x: geo.size.width * progress - 1)
                    }
                }
                .frame(height: 70)
        }
    }

    private var controls: some View {
        VStack(spacing: Spacing.s) {
            Slider(value: $progress, in: 0...1)
                .tint(Color.rc.accent)
                .accessibilityLabel("Position dans la sortie")
            HStack {
                Picker("Vitesse", selection: $speed) {
                    Text("×1").tag(1)
                    Text("×2").tag(2)
                    Text("×4").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Spacer()
                Button {
                    if progress >= 1 { progress = 0 }
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(Color.rc.onAccent)
                        .frame(width: 60, height: 60)
                        .background(Color.rc.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Lecture")
            }
        }
    }

    // MARK: - Données

    private func makeChartPoints() -> [ChartPoint] {
        let column: [Double]?
        switch metric {
        case 1: column = track?.hr
        case 2: column = track?.ele
        default: column = track?.speed
        }
        guard let values = column, !values.isEmpty else { return [] }
        let step = max(1, values.count / 120)
        var points: [ChartPoint] = []
        var i = 0
        while i < values.count {
            points.append(ChartPoint(x: Double(i), y: values[i]))
            i += step
        }
        return points
    }

    private func value(_ column: [Double]?) -> Double {
        guard let column = column, index < column.count else { return 0 }
        return column[index]
    }

    private func number(_ column: [Double]?) -> String {
        guard let column = column, index < column.count else { return "–" }
        return "\(Int(column[index].rounded()))"
    }
}

struct ChartPoint: Identifiable {
    let x: Double
    let y: Double
    var id: Double { x }
}

/// Courbe sans axes, sur toute la largeur (`x` de 0 à `xMax`).
struct ReplayChart: View {
    let points: [ChartPoint]
    let xMax: Double

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Position", point.x), y: .value("Valeur", point.y))
                    .foregroundStyle(Color.rc.accent)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...xMax)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityLabel("Courbe de la sortie")
    }
}

struct ReplayStat: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.rcLabel)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.65))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.rcStat)
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.65))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value) \(unit)")
    }
}
