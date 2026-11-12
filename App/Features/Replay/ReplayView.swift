import SwiftUI
import MapKit
import Charts
import RunCoachCore

/// Replay d'une sortie : carte à plat qui tourne avec le coureur (il avance toujours vers le haut de l'écran).
/// Pas de relief 3D : les arbres et bâtiments 3D y masquaient le tracé.
// shortcut: étape 1 = maquette. Horloge simple (sortie entière en 60 s à ×1) et point qui saute d'un relevé
// au suivant ; l'étape 3 cale la lecture sur l'allure réelle et lisse le déplacement (ARCHITECTURE.md §8).
struct ReplayView: View {
    let run: Run
    /// 0 = satellite, 1 = plan.
    @State var style = 0
    @Environment(\.dismiss) private var dismiss
    @State private var track: Track?
    @State private var coordinates: [CLLocationCoordinate2D] = []
    @State private var progress: Double = 0.4
    @State private var isPlaying = false
    @State private var speed = 1
    @State private var metric = 0
    @State private var position: MapCameraPosition = .automatic
    @State private var streetScene: MKLookAroundScene?
    @State private var showStreet = false
    @State private var noStreet = false

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
        .task {
            guard track == nil else { return }
            let loaded = run.loadTrack()
            track = loaded
            coordinates = RouteMap.coordinates(loaded)
            updateCamera()
        }
        .onChange(of: progress) {
            updateCamera()
        }
        .onChange(of: style) {
            updateCamera()
        }
        .task(id: isPlaying) {
            while isPlaying, progress < 1, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                progress = min(1, progress + 0.05 / 60 * Double(speed))
            }
            if progress >= 1 { isPlaying = false }
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

    private var map: some View {
        Map(position: $position) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.white.opacity(0.55), lineWidth: 4)
                MapPolyline(coordinates: Array(coordinates.prefix(max(2, index + 1))))
                    .stroke(Color.rc.accent, lineWidth: 5)
                // Disque posé au sol et non `Annotation` : sur le simulateur iOS 26.5, une `Annotation`
                // n'apparaît pas quand la carte est inclinée (constat de la CI).
                MapCircle(center: coordinates[index], radius: 10)
                    .foregroundStyle(Color.rc.accent)
                    .stroke(Color.white, lineWidth: 4)
            }
        }
        .mapStyle(style == 1 ? .standard(elevation: .flat) : .imagery(elevation: .flat))
        .ignoresSafeArea()
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
            mapButton(style == 0 ? "globe.europe.africa.fill" : "map.fill", label: "Style de carte") {
                style = (style + 1) % 2
            }
            .accessibilityValue(style == 0 ? "Satellite" : "Plan")
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
            ReplayChart(points: chartPoints, cursor: Double(index))
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

    private var chartPoints: [ChartPoint] {
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

    private func updateCamera() {
        guard coordinates.count > 1 else { return }
        // Cap = sens de la course : le coureur avance vers le haut de l'écran. Légère inclinaison, vue « derrière lui ».
        position = .camera(MapCamera(
            centerCoordinate: coordinates[index],
            distance: 600,
            heading: track?.heading(at: index) ?? 0,
            pitch: 45
        ))
    }
}

struct ChartPoint: Identifiable {
    let x: Double
    let y: Double
    var id: Double { x }
}

/// Courbe sans axes avec un curseur vertical à la position courante.
struct ReplayChart: View {
    let points: [ChartPoint]
    let cursor: Double

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Position", point.x), y: .value("Valeur", point.y))
                    .foregroundStyle(Color.rc.accent)
                    .interpolationMethod(.catmullRom)
            }
            RuleMark(x: .value("Position", cursor))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
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
