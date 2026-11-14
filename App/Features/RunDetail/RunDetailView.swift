import SwiftUI
import SwiftData
import MapKit
import Charts
import RunCoachCore

/// Détail d'une sortie. Information principale : distance et allure.
struct RunDetailView: View {
    let run: Run
    @State private var track: Track?
    @State private var showReplay = false
    /// Point de la sortie sous le doigt (km), pendant un appui prolongé sur une courbe.
    @State private var selectedKm: Double?
    @Query private var allRuns: [Run]
    @State private var records: [String] = []
    @State private var celebrate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if run.track != nil {
                    mapHeader
                }
                if !records.isEmpty {
                    recordBanner
                }
                summary
                if !run.isStrength {
                    effortCard
                }
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
                           points: series(track?.speed) { 1000 / max($0, 1) }, isPace: true,
                           selectedKm: $selectedKm, detail: detail(atKm:))
                TrackChart(title: "Fréquence cardiaque", summary: run.avgHR.map { "moy. \($0) bpm" } ?? "",
                           points: series(track?.hr), selectedKm: $selectedKm, detail: detail(atKm:))
                TrackChart(title: "Altitude", summary: run.elevationGainM.map { "D+ \(Int($0.rounded())) m" } ?? "",
                           points: series(track?.ele), isFilled: true, selectedKm: $selectedKm, detail: detail(atKm:))
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
            records = run.records(among: allRuns)
            if !records.isEmpty { celebrate = true }
        }
        .sensoryFeedback(.success, trigger: celebrate) { _, new in new }
        .fullScreenCover(isPresented: $showReplay) {
            ReplayView(run: run)
        }
    }

    /// Célébration d'un record battu par cette sortie (étape 7, n° 6).
    private var recordBanner: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "trophy.fill")
                .font(.title)
                .foregroundStyle(Color.rc.warning)
                .symbolEffect(.bounce, value: celebrate)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(records.count > 1 ? "Records personnels" : "Record personnel")
                    .font(.rcHeadline)
                    .foregroundStyle(Color.rc.textPrimary)
                Text(records.joined(separator: " · "))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.rc.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .rcCard()
        .scaleEffect(celebrate ? 1 : 0.9)
        .opacity(celebrate ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: celebrate)
        .accessibilityElement(children: .combine)
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
            if run.distanceM > 0 {
                HeroNumber(value: Fmt.km(run.distanceM), unit: "km")
                HStack(spacing: Spacing.xl) {
                    Label(Fmt.duration(run.durationS), systemImage: "clock")
                    Label(Fmt.pace(sPerKm: run.paceSPerKm) + " /km", systemImage: "speedometer")
                }
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.rc.textPrimary)
            } else {
                // Activité sans distance (renfo) : la durée devient le chiffre principal.
                HeroNumber(value: Fmt.duration(run.durationS))
            }
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
            // Renfo : pas de carte de ressenti modifiable, la valeur reste affichée ici.
            if run.isStrength, let effort = run.perceivedEffort {
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

    /// Ressenti de 1 à 10 : il affine les allures calculées (§6.3) ; sans lui, l'effort est supposé modéré.
    private var effortCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ressenti").rcLabel()
                Text("Sert au coach à ajuster tes allures.")
                    .font(.caption)
                    .foregroundStyle(Color.rc.textSecondary)
            }
            Spacer()
            Picker("Ressenti", selection: Binding(get: { run.perceivedEffort ?? 0 },
                                                  set: { run.perceivedEffort = $0 == 0 ? nil : $0 })) {
                Text("Non noté").tag(0)
                ForEach(1...10, id: \.self) { value in
                    Text("\(value) · " + Self.effortNames[value - 1]).tag(value)
                }
            }
            .pickerStyle(.menu)
        }
        .rcCard()
    }

    private static let effortNames = ["très facile", "facile", "facile", "modéré", "modéré", "soutenu", "soutenu",
                                      "difficile", "très difficile", "maximal"]

    /// « km 3,42 · 21:30 · 6:12 /km · 152 bpm · 45 m » : toutes les mesures au point choisi.
    private func detail(atKm km: Double) -> String {
        guard let track, track.dist.count > 1 else { return "" }
        let i = min(track.dist.count - 1, Int(track.index(atDistanceM: km * 1000).rounded()))
        var parts = ["km " + Fmt.decimal(km, decimals: 2), Fmt.duration(track.t[i])]
        if let speed = track.speed?[i] { parts.append(Fmt.pace(sPerKm: 1000 / max(speed, 1)) + " /km") }
        if let hr = track.hr?[i] { parts.append("\(Int(hr.rounded())) bpm") }
        if let ele = track.ele?[i] { parts.append("\(Int(ele.rounded())) m") }
        return parts.joined(separator: " · ")
    }

    private func plannedCard(_ planned: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Séance prévue")
            WorkoutBadge(kind: planned.kindValue)
            Text(plannedComparison(planned))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color.rc.textSecondary)
            if let exercises = planned.spec?.exercises, !exercises.isEmpty {
                ExerciseList(exercises: exercises, color: planned.kindValue.color)
                    .padding(.top, Spacing.s)
            }
        }
        .rcCard()
    }

    private func plannedComparison(_ planned: PlannedWorkout) -> String {
        var text = "Prévu : \(planned.title)"
        if let km = planned.estimatedDistanceKm {
            text += ", " + Fmt.decimal(km, decimals: 1) + " km"
        }
        return text + " · Fait : " + (run.distanceM > 0 ? Fmt.km(run.distanceM, decimals: 1) + " km" : Fmt.duration(run.durationS))
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
    /// Appui prolongé puis glissement : le point choisi (km), commun à toutes les courbes de la sortie.
    @Binding var selectedKm: Double?
    let detail: (_ atKm: Double) -> String

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
                // Toujours présente (vide hors sélection) : la carte ne change pas de hauteur sous le doigt.
                Text(selectedKm.map(detail) ?? " ")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.rc.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
                    if let selectedKm {
                        RuleMark(x: .value("Point choisi", selectedKm))
                            .foregroundStyle(Color.rc.textPrimary)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        // Appui prolongé d'abord : un glissement direct continue de faire défiler la page.
                        Rectangle().fill(Color.clear).contentShape(Rectangle())
                            .gesture(
                                LongPressGesture(minimumDuration: 0.25)
                                    .sequenced(before: DragGesture(minimumDistance: 0))
                                    .onChanged { value in
                                        guard case .second(true, let drag?) = value, let plot = proxy.plotFrame else { return }
                                        let x = drag.location.x - geo[plot].origin.x
                                        if let km: Double = proxy.value(atX: x) {
                                            selectedKm = min(max(km, points.first?.x ?? 0), points.last?.x ?? km)
                                        }
                                    }
                                    .onEnded { _ in selectedKm = nil }
                            )
                    }
                }
                .sensoryFeedback(.selection, trigger: selectedKm == nil)
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
