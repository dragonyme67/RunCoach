import SwiftUI
import MapKit
import Charts
import SwiftData
import RunCoachCore

/// Replay d'une sortie : carte qui tourne avec le coureur (il avance toujours vers le haut de l'écran).
/// Par défaut, satellite vu du dessus ; le tracé est dessiné par-dessus la carte (`ReplayMapView`).
/// Entrée : vue d'ensemble du tracé, puis descente vers le départ ; la lecture démarre seule.
/// Sortie : remontée vers la vue d'ensemble et carte de bilan (ARCHITECTURE.md §8, 3.2).
/// Fluidité : la lecture avance à vitesse constante sur la distance (marche et arrêts ne la ralentissent pas),
/// la position est interpolée à chaque image, et la caméra tourne en douceur vers un point situé devant.
/// Effets (3.3, 3.4 en partie) : halo qui bat au rythme cardiaque dans la couleur de la zone, bulle à chaque
/// kilomètre avec un léger retour haptique, bandeau réduit à une ligne pendant la lecture.
struct ReplayView: View {
    let run: Run
    /// 0 = satellite vu du dessus, 1 = relief 3D, 2 = plan incliné.
    @State var style = 0
    /// Position de lecture, fraction des relevés (0 = départ).
    @State var progress: Double = 0
    /// Temps écoulé dans la séquence d'entrée ; `nil` quand elle est finie (ou désactivée).
    @State var intro: Double? = 0
    /// Temps écoulé dans la séquence de sortie ; `nil` hors sortie.
    @State private var outro: Double?
    @State private var showSummary = false
    @State private var overview: ReplayCamera?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Cap de la caméra, lissé (`ReplayDirector.smoothHeading`).
    @State private var cameraHeading: Double = 0
    /// Indices des points dessinés en surimpression : un tous les 12 m environ.
    @State private var overlayIndices: [Int] = []
    @Environment(\.dismiss) private var dismiss
    @State private var track: Track?
    @State private var coordinates: [CLLocationCoordinate2D] = []
    @State var isPlaying = false
    @State private var speed = 1
    @State private var metric = 0
    @State private var streetScene: MKLookAroundScene?
    @State private var showStreet = false
    @State private var noStreet = false
    @State private var chartPoints: [ChartPoint] = []
    @Query private var profiles: [AthleteProfile]
    /// Relevé affiché dans le bandeau : rafraîchi 4 fois par seconde au plus, pour que les chiffres restent lisibles.
    @State private var hudIndex = 0
    @State private var hudAgeS: Double = 0
    /// Position dans le battement de cœur en cours, de 0 à 1 (halo du coureur).
    @State private var beat: Double = 0
    /// Kilomètre qui vient d'être franchi, affiché 2 s au-dessus du coureur.
    @State private var kmBubble: Int?
    @State private var kmBubbleAgeS: Double = 0
    /// Pendant la lecture, bandeau réduit à une ligne ; toucher la carte l'agrandit ou le réduit.
    @State private var compact = true

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
            Group {
                if showSummary { summary } else if isPlaying && compact { compactPanel } else { panel }
            }
            .animation(.rcStandard, value: isPlaying && compact)
        }
        .background { clock }
        .task {
            guard track == nil else { return }
            let loaded = run.loadTrack()
            track = loaded
            coordinates = RouteMap.coordinates(loaded)
            overlayIndices = Self.overlayIndices(loaded?.dist ?? [], stepM: 12)
            overview = loaded.map { ReplayDirector.overview(of: $0, viewAspect: 0.46) }
            chartPoints = makeChartPoints()
            cameraHeading = targetHeading
            hudIndex = index
            // « Réduire les animations » d'iOS : pas de séquence d'entrée.
            if reduceMotion { intro = nil }
        }
        .onChange(of: progress) {
            // Barre déplacée à la main, lecture en pause : la caméra se tourne directement dans le bon sens.
            if !isPlaying {
                cameraHeading = targetHeading
                hudIndex = index
            }
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
        .sensoryFeedback(.impact(weight: .light), trigger: kmBubble) { _, new in new != nil }
    }

    /// Horloge de lecture, calée sur le rafraîchissement de l'écran.
    private var clock: some View {
        TimelineView(.animation(paused: !isPlaying && intro == nil && outro == nil)) { context in
            Color.clear.onChange(of: context.date) { old, new in
                // Borné : à la reprise après une pause, l'écart entre deux dates vaut toute la pause.
                tick(min(0.1, new.timeIntervalSince(old)))
            }
        }
    }

    private func tick(_ elapsedS: Double) {
        guard let track, let start = track.dist.first, let end = track.dist.last, end > start else { return }
        if let t = intro {
            let next = t + elapsedS
            if next >= ReplayDirector.introHoldS + ReplayDirector.introDescentS {
                intro = nil
                isPlaying = true
            } else {
                intro = next
            }
            return
        }
        if let t = outro {
            let next = t + elapsedS
            if next >= ReplayDirector.outroS {
                outro = nil
                showSummary = true
            } else {
                outro = next
            }
            return
        }
        let playS = ReplayDirector.playbackDurationS(runDurationS: track.t.last ?? run.durationS)
        let before = currentDistM
        let distanceM = min(end, before + elapsedS * Double(speed) * (end - start) / playS)
        progress = track.index(atDistanceM: distanceM) / Double(max(1, track.dist.count - 1))
        cameraHeading = ReplayDirector.smoothHeading(cameraHeading, toward: targetHeading, dt: elapsedS)

        hudAgeS += elapsedS
        if hudAgeS >= 0.25 {
            hudAgeS = 0
            hudIndex = index
        }
        // Le halo bat au rythme réel du cœur à cet endroit, pas à la vitesse de lecture.
        if !reduceMotion, let hr = track.hr, index < hr.count {
            beat = (beat + elapsedS * hr[index] / 60).truncatingRemainder(dividingBy: 1)
        }
        if Int(distanceM / 1000) > Int(before / 1000) {
            withAnimation(.rcStandard) { kmBubble = Int(distanceM / 1000) }
            kmBubbleAgeS = 0
        } else if kmBubble != nil {
            kmBubbleAgeS += elapsedS
            if kmBubbleAgeS >= 2 { withAnimation(.rcStandard) { kmBubble = nil } }
        }
        if distanceM >= end {
            isPlaying = false
            kmBubble = nil
            if reduceMotion { showSummary = true } else { outro = 0 }
        }
    }

    /// Caméra du moment : suivi du coureur, ou passage vers et depuis la vue d'ensemble.
    private func camera(_ track: Track) -> ReplayCamera {
        let runner = track.coordinate(atDistanceM: currentDistM)
        // Le satellite sans relief ignore l'inclinaison (constaté sur MapKit) : il reste vu du dessus.
        let follow = ReplayCamera(centerLat: runner.lat, centerLon: runner.lon,
        // Vues inclinées : caméra haute (1 400 m), demandée par l'utilisateur le 2026-11-14 pour voir loin devant.
                                  distanceM: style == 0 ? 600 : 2200, pitchDeg: style == 0 ? 0 : 60,
                                  headingDeg: cameraHeading)
        guard let overview else { return follow }
        if let t = intro {
            return ReplayDirector.blend(overview, follow, t: (t - ReplayDirector.introHoldS) / ReplayDirector.introDescentS)
        }
        if let t = outro { return ReplayDirector.blend(follow, overview, t: t / ReplayDirector.outroS) }
        return showSummary ? overview : follow
    }

    /// Revoir : repart de la vue d'ensemble, comme à l'ouverture.
    private func replay() {
        showSummary = false
        progress = 0
        cameraHeading = targetHeading
        intro = reduceMotion ? nil : 0
        isPlaying = reduceMotion
    }

    /// Cap visé : la direction d'un point situé un peu plus loin sur le tracé.
    private var targetHeading: Double {
        track?.bearing(atDistanceM: currentDistM, aheadM: ReplayDirector.lookAheadM) ?? 0
    }

    @ViewBuilder
    private var map: some View {
        if let track, coordinates.count > 1 {
            let pose = track.pose(at: progress)
            // Pendant le suivi, seule la partie proche est dessinée ; vue d'ensemble : tout le tracé.
            let following = intro == nil && outro == nil && !showSummary
            ReplayMapView(coordinates: overlayIndices.map { coordinates[$0] },
                          distances: overlayIndices.map { track.dist[$0] },
                          currentDistM: currentDistM,
                          runner: CLLocationCoordinate2D(latitude: pose.lat, longitude: pose.lon),
                          camera: camera(track),
                          style: style,
                          behindM: following ? (style == 0 ? 600 : 2000) : .infinity,
                          aheadM: following ? (style == 0 ? 1500 : 6000) : .infinity,
                          haloColor: haloColor,
                          pulse: reduceMotion ? 0.3 : beat)
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .overlay {
                    // Le coureur est au centre de la carte, qui occupe tout l'écran : la bulle est juste au-dessus.
                    if let km = kmBubble {
                        Text(kmText(km))
                            .font(.rcHeadline)
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, Spacing.s)
                            .background(.ultraThinMaterial, in: Capsule())
                            .environment(\.colorScheme, .dark)
                            .offset(y: -52)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isPlaying { compact.toggle() }
                }
        } else {
            Color.rc.background.ignoresSafeArea()
        }
    }

    /// Couleur de la zone cardiaque du moment ; sans FC ou sans profil, pas de halo.
    private var haloColor: UIColor {
        guard let hr = track?.hr, hudIndex < hr.count, let maxBpm else { return .clear }
        return UIColor(Color.rc.zone(HeartZones.zone(bpm: hr[hudIndex], maxBpm: maxBpm)))
    }

    /// FC max : saisie dans le profil, sinon estimée par l'âge (ARCHITECTURE.md §6.3).
    private var maxBpm: Double? {
        guard let profile = profiles.first else { return nil }
        if let hrMax = profile.hrMax { return Double(hrMax) }
        return HeartZones.estimatedMaxBpm(ageYears: profile.birthDate.distance(to: Date()) / (365.25 * 86_400))
    }

    /// « km 3 · 6:19 » : le kilomètre franchi et son allure.
    private func kmText(_ km: Int) -> String {
        guard let split = run.sortedSplits.first(where: { $0.index == km }) else { return "km \(km)" }
        return "km \(km) · \(Fmt.pace(sPerKm: split.paceSPerKm))"
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
            mapButton(["globe.europe.africa.fill", "view.3d", "map.fill"][style], label: "Style de carte") {
                style = (style + 1) % 3
            }
            .accessibilityValue(["Satellite vu du dessus", "Relief 3D", "Plan incliné"][style])
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
            ReplaySegments(title: "Courbe", labels: ["Allure", "FC", "Altitude"], values: [0, 1, 2], selection: $metric)
                .equatable()
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
                ReplaySegments(title: "Vitesse", labels: ["×1", "×2", "×4"], values: [1, 2, 4], selection: $speed)
                    .equatable()
                    .frame(width: 150)
                Spacer()
                playButton(size: 60)
            }
        }
    }

    private func playButton(size: CGFloat) -> some View {
        Button {
            if progress >= 1 { progress = 0 }
            // Pendant l'entrée : on la saute et la lecture démarre tout de suite.
            if intro != nil {
                intro = nil
                isPlaying = true
            } else {
                isPlaying.toggle()
            }
        } label: {
            Image(systemName: isPlaying || intro != nil ? "pause.fill" : "play.fill")
                .font(size < 60 ? .headline : .title2)
                .foregroundStyle(Color.rc.onAccent)
                .frame(width: size, height: size)
                .background(Color.rc.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Lecture")
    }

    /// Bandeau réduit pendant la lecture : une ligne de chiffres ; la toucher rouvre le bandeau complet.
    private var compactPanel: some View {
        HStack(spacing: Spacing.m) {
            Button {
                compact = false
            } label: {
                HStack(spacing: Spacing.m) {
                    compactStat(Fmt.pace(speedMps: value(track?.speed)), unit: "/km")
                    compactStat(number(track?.hr), unit: "bpm")
                    compactStat(Fmt.km(value(track?.dist)), unit: "km")
                    compactStat(Fmt.duration(value(track?.t)), unit: "")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Affiche le détail")
            .accessibilityIdentifier("hud-compact")
            playButton(size: 44)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.horizontal, Spacing.s)
        .environment(\.colorScheme, .dark)
    }

    private func compactStat(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.rcHeadline)
                .monospacedDigit()
                .foregroundStyle(Color.white)
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// Bilan de fin : la sortie en quatre chiffres, puis Revoir ou Fermer.
    private var summary: some View {
        VStack(spacing: Spacing.l) {
            Text("Sortie terminée")
                .font(.rcTitle)
                .foregroundStyle(Color.white)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 2), spacing: Spacing.m) {
                ReplayStat(label: "Distance", value: Fmt.km(run.distanceM), unit: "km")
                ReplayStat(label: "Durée", value: Fmt.duration(run.durationS), unit: "")
                ReplayStat(label: "Allure", value: Fmt.pace(sPerKm: run.paceSPerKm), unit: "/km")
                if let best = run.sortedSplits.filter({ $0.distanceM >= 990 }).map(\.paceSPerKm).min() {
                    ReplayStat(label: "Meilleur km", value: Fmt.pace(sPerKm: best), unit: "/km")
                }
            }
            HStack(spacing: Spacing.m) {
                Button("Revoir") { replay() }
                    .buttonStyle(.bordered)
                    .tint(Color.white)
                    .frame(maxWidth: .infinity)
                PrimaryButton(title: "Fermer") { dismiss() }
            }
        }
        .padding(Spacing.l)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.horizontal, Spacing.s)
        .environment(\.colorScheme, .dark)
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
        guard let column = column, hudIndex < column.count else { return 0 }
        return column[hudIndex]
    }

    private func number(_ column: [Double]?) -> String {
        guard let column = column, hudIndex < column.count else { return "–" }
        return "\(Int(column[hudIndex].rounded()))"
    }
}

/// Sélecteur segmenté redessiné seulement quand son choix change. Pendant la lecture, l'écran est recalculé
/// à chaque image ; un `Picker` segmenté mis à jour aussi souvent perdait les touchers (vu sur l'iPhone, reproduit par la CI).
struct ReplaySegments: View, Equatable {
    let title: String
    let labels: [String]
    let values: [Int]
    @Binding var selection: Int

    static func == (a: Self, b: Self) -> Bool {
        a.selection == b.selection && a.labels == b.labels
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(values.indices, id: \.self) { i in
                Text(labels[i]).tag(values[i])
            }
        }
        .pickerStyle(.segmented)
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
