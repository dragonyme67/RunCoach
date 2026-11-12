import SwiftUI
import MapKit
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
                        ZoneBar(seconds: run.hrZoneSeconds)
                    }
                    .rcCard()
                }
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

/// Splits par kilomètre : barres dont la longueur suit l'allure.
struct SplitsCard: View {
    let splits: [Split]

    var body: some View {
        let slowest = max(1, splits.map { $0.paceSPerKm }.max() ?? 1)
        let fastest = splits.map { $0.paceSPerKm }.min() ?? 0
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Par kilomètre")
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
