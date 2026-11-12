import SwiftUI
import MapKit
import Charts
import RunCoachCore

/// Détail d'une sortie. Information principale : distance et allure.
struct RunDetailView: View {
    let run: Run
    @State private var track: Track?
    @State private var showReplay = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                mapHeader
                summary
                tiles
                if run.hrZoneSeconds.count == 5 {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        SectionHeader(title: "Zones cardiaques")
                        ZoneBreakdown(seconds: run.hrZoneSeconds)
                    }
                    .rcCard()
                }
                // shortcut: une allure à l'arrêt est plafonnée à 16:40 /km pour ne pas écraser la courbe ;
                // à revoir à l'étape 2 avec de vraies sorties (pauses, feux rouges).
                TrackChart(title: "Allure", summary: "moy. " + Fmt.pace(sPerKm: run.paceSPerKm) + " /km",
                           points: series(track?.speed) { 1000 / max($0, 1) }, isPace: true)
                TrackChart(title: "Fréquence cardiaque", summary: run.avgHR.map { "moy. \($0) bpm" } ?? "",
                           points: series(track?.hr))
                TrackChart(title: "Altitude", summary: run.elevationGainM.map { "D+ \(Int($0.rounded())) m" } ?? "",
                           points: series(track?.ele), isFilled: true)
                if !run.splits.isEmpty {
                    SplitsCard(splits: run.sortedSplits)
                }
                if let planned = run.plannedWorkout {
                    plannedCard(planned)
                }
            }
            .padding(Spacing.l)
        }
        .rcScreenBackground()
        .navigationTitle(run.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if track == nil { track = run.loadTrack() }
        }
        .fullScreenCover(isPresented: $showReplay) {
            ReplayView(run: run)
        }
    }

    private var mapHeader: some View {
        ZStack(alignment: .bottom) {
            RouteMap(track: track)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .allowsHitTesting(false)
            Button {
                showReplay = true
            } label: {
                Label("Rejouer", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(Color.rc.onAccent)
                    .padding(.horizontal, Spacing.xl)
                    .frame(minHeight: 50)
                    .background(Color.rc.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, Spacing.l)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(run.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "fr_FR"))))
                .rcLabel()
            HeroNumber(value: Fmt.km(run.distanceM), unit: "km")
            HStack(spacing: Spacing.xl) {
                Label(Fmt.duration(run.durationS), systemImage: "clock")
                Label(Fmt.pace(sPerKm: run.paceSPerKm) + " /km", systemImage: "speedometer")
            }
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color.rc.textPrimary)
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.m)], spacing: Spacing.m) {
            if let hr = run.avgHR {
                StatTile(label: "FC moyenne", value: "\(hr)", unit: "bpm", icon: "heart.fill")
            }
            if let cadence = run.avgCadenceSpm {
                StatTile(label: "Cadence", value: "\(Int(cadence.rounded()))", unit: "pas/min", icon: "metronome.fill")
            }
            if let gain = run.elevationGainM {
                StatTile(label: "Dénivelé", value: "\(Int(gain.rounded()))", unit: "m", icon: "mountain.2.fill")
            }
            if let calories = run.calories {
                StatTile(label: "Calories", value: "\(Int(calories.rounded()))", unit: "kcal", icon: "flame.fill")
            }
            if let temperature = run.avgTemperatureC {
                StatTile(label: "Température", value: "\(Int(temperature.rounded()))", unit: "°C", icon: "thermometer.medium")
            }
            if let vo2max = run.vo2max {
                StatTile(label: "VO2max", value: "\(Int(vo2max.rounded()))", icon: "lungs.fill")
            }
            if let load = run.edwardsLoad {
                StatTile(label: "Charge", value: "\(Int(load.rounded()))", icon: "bolt.heart.fill")
            }
            if let effort = run.perceivedEffort {
                StatTile(label: "Ressenti", value: "\(effort)", unit: "/ 10", icon: "face.smiling")
            }
        }
    }

    /// Une colonne du tracé en fonction de la distance (km), réduite à 120 points environ.
    private func series(_ column: [Double]?, transform: (Double) -> Double = { $0 }) -> [ChartPoint] {
        guard let track = track, let values = column else { return [] }
        let n = min(values.count, track.dist.count)
        return stride(from: 0, to: n, by: max(1, n / 120)).map {
            ChartPoint(x: track.dist[$0] / 1000, y: transform(values[$0]))
        }
    }

    private func plannedCard(_ planned: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Séance prévue")
            WorkoutBadge(kind: planned.kindValue)
            Text(plannedComparison(planned))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color.rc.textSecondary)
        }
        .rcCard()
    }

    private func plannedComparison(_ planned: PlannedWorkout) -> String {
        var text = "Prévu : \(planned.title)"
        if let km = planned.estimatedDistanceKm {
            text += ", " + Fmt.decimal(km, decimals: 1) + " km"
        }
        return text + " · Fait : " + Fmt.km(run.distanceM, decimals: 1) + " km"
    }
}

/// Carte satellite à plat avec le tracé complet. Non interactive.
struct RouteMap: View {
    let track: Track?

    var body: some View {
        let coordinates = RouteMap.coordinates(track)
        Map(initialPosition: .automatic, interactionModes: []) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.rc.accent, lineWidth: 4)
            }
        }
        .mapStyle(.imagery(elevation: .flat))
        .accessibilityLabel("Carte du tracé")
    }

    static func coordinates(_ track: Track?) -> [CLLocationCoordinate2D] {
        guard let track = track else { return [] }
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(track.count)
        for i in 0..<min(track.lat.count, track.lon.count) {
            out.append(CLLocationCoordinate2D(latitude: track.lat[i], longitude: track.lon[i]))
        }
        return out
    }
}

/// Courbe d'une mesure le long de la sortie, avec sa moyenne en pointillé. Masquée sans données.
struct TrackChart: View {
    let title: String
    let summary: String
    /// `x` en km.
    let points: [ChartPoint]
    /// Valeurs en s/km : axe inversé (plus haut = plus rapide) et libellés en min:s.
    var isPace = false
    var isFilled = false

    var body: some View {
        if points.count > 1 {
            let mean = points.reduce(0) { $0 + $1.y } / Double(points.count)
            let low = points.map { $0.y }.min() ?? 0
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: title)
                    Spacer()
                    Text(summary)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.rc.textSecondary)
                }
                Chart {
                    ForEach(points) { point in
                        if isFilled {
                            AreaMark(x: .value("km", point.x), yStart: .value("Base", low), yEnd: .value(title, point.y))
                                .foregroundStyle(Color.rc.accentText.opacity(0.2))
                                .interpolationMethod(.catmullRom)
                        }
                        LineMark(x: .value("km", point.x), y: .value(title, point.y))
                            .foregroundStyle(Color.rc.accentText)
                            .interpolationMethod(.catmullRom)
                    }
                    if !isFilled {
                        RuleMark(y: .value("Moyenne", mean))
                            .foregroundStyle(Color.rc.textSecondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: isPace))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(isPace ? Fmt.pace(sPerKm: number) : "\(Int(number.rounded()))")
                            }
                        }
                    }
                }
                .chartXAxisLabel("km")
                .frame(height: 130)
                .accessibilityLabel("\(title) le long de la sortie, \(summary)")
            }
            .rcCard()
        }
    }
}

/// Splits par kilomètre : barres dont la longueur suit l'allure.
struct SplitsCard: View {
    let splits: [Split]

    var body: some View {
        let slowest = max(1, splits.map { $0.paceSPerKm }.max() ?? 1)
        let fastest = splits.map { $0.paceSPerKm }.min() ?? 0
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Par kilomètre")
            HStack(spacing: Spacing.m) {
                Text("km").frame(width: 22, alignment: .trailing)
                Spacer()
                Text("allure").frame(width: 48, alignment: .trailing)
                Text("FC").frame(width: 34, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(Color.rc.textSecondary)
            .accessibilityHidden(true)
            ForEach(splits) { split in
                HStack(spacing: Spacing.m) {
                    Text("\(split.index)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.rc.textSecondary)
                        .frame(width: 22, alignment: .trailing)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(split.paceSPerKm == fastest ? Color.rc.accent : Color.rc.accent.opacity(0.45))
                            .frame(width: geo.size.width * fraction(split.paceSPerKm, fastest: fastest, slowest: slowest))
                    }
                    .frame(height: 18)
                    Text(Fmt.pace(sPerKm: split.paceSPerKm))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.rc.textPrimary)
                        .frame(width: 48, alignment: .trailing)
                    Text(split.avgHR.map { "\($0)" } ?? "–")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.rc.textSecondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kilomètre \(split.index), \(Fmt.pace(sPerKm: split.paceSPerKm)) par kilomètre")
            }
        }
        .rcCard()
    }

    /// Plus l'allure est rapide, plus la barre est longue : la plus rapide est pleine, la plus lente à 55 %.
    private func fraction(_ pace: Double, fastest: Double, slowest: Double) -> CGFloat {
        guard slowest > fastest else { return 1 }
        return CGFloat(0.55 + 0.45 * (slowest - pace) / (slowest - fastest))
    }
}
