import SwiftUI
import SwiftData
import MapKit
import RunCoachCore

/// Carte de chaleur (étape 7, n° 8) : tous les parcours superposés en traits translucides, plus vifs là où l'on
/// passe souvent. Calculée et affichée uniquement sur l'iPhone ; les tracés ne quittent jamais l'appareil.
struct RunsHeatmapView: View {
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @State private var lines: [[CLLocationCoordinate2D]] = []
    @State private var loading = true

    var body: some View {
        ZStack {
            Map(initialPosition: .automatic) {
                ForEach(lines.indices, id: \.self) { i in
                    MapPolyline(coordinates: lines[i])
                        .stroke(Color.rc.accent.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .id(lines.count)
            if loading {
                ProgressView("Tracés…")
                    .padding(Spacing.l)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            } else if lines.isEmpty {
                EmptyState(icon: "map", title: "Aucun tracé", message: "Tes sorties avec GPS apparaîtront ici.")
                    .rcCard()
                    .padding(Spacing.l)
            }
        }
        .navigationTitle("Mes parcours")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Lecture sur le fil principal (SwiftData), décodage à côté : des centaines de tracés.
            let blobs = runs.filter(\.isRunning).compactMap { $0.track?.samplesData }
            lines = await Task.detached(priority: .userInitiated) { Self.simplified(blobs) }.value
            loading = false
        }
        .accessibilityLabel("Carte de toutes tes sorties")
    }

    /// 200 points au plus par sortie : assez pour la forme du parcours, léger à dessiner.
    nonisolated private static func simplified(_ blobs: [Data]) -> [[CLLocationCoordinate2D]] {
        blobs.compactMap { data in
            guard let track = try? JSONDecoder().decode(Track.self, from: data), track.lat.count > 1 else { return nil }
            let n = min(track.lat.count, track.lon.count)
            let step = max(1, n / 200)
            return stride(from: 0, to: n, by: step).map { CLLocationCoordinate2D(latitude: track.lat[$0], longitude: track.lon[$0]) }
        }
    }
}
