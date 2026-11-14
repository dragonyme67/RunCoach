import SwiftUI
import WidgetKit
import RunCoachCore

/// Widgets de RunCoach (étape 7, n° 11) : séance du jour et km de la semaine, sur l'écran d'accueil et l'écran
/// verrouillé. Ils lisent le résumé écrit par l'app (`WidgetBridge`) dans le conteneur partagé.
@main
struct RunCoachWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    /// nil : l'app n'a encore rien écrit, ou le résumé date d'un autre jour.
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: WidgetSnapshot(
            day: DayKey.key(Date()),
            today: [.init(kind: .easy, title: "Footing", durationMin: 35, distanceKm: 5, done: false)],
            next: nil, nextDay: nil, weekDoneKm: 8, weekPlannedKm: 18))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : TodayEntry(date: Date(), snapshot: Self.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // Relu juste après minuit : la séance du jour change, et l'app le réécrit à chaque ouverture.
        let midnight = DayKey.calendar.startOfDay(for: DayKey.addDays(1, to: Date())).addingTimeInterval(60)
        completion(Timeline(entries: [TodayEntry(date: Date(), snapshot: Self.read())], policy: .after(midnight)))
    }

    static func read() -> WidgetSnapshot? {
        let group = WidgetSnapshot.appGroup(info: Bundle.main.infoDictionary)
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? Data(contentsOf: folder.appendingPathComponent(WidgetSnapshot.fileName)),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.day == DayKey.key(Date()) else { return nil }
        return snapshot
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.rc.surface }
        }
        .configurationDisplayName("Séance du jour")
        .description("Ta séance du jour et tes km de la semaine.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryCircular: ring(snapshot)
            case .accessoryRectangular: lockLine(snapshot)
            case .systemMedium: medium(snapshot)
            default: small(snapshot)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "figure.run")
                Text("Ouvre RunCoach pour voir ta séance")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    /// Séance du jour : la première pas encore faite, sinon la dernière.
    private func main(_ s: WidgetSnapshot) -> WidgetSnapshot.Session? {
        s.today.first { !$0.done } ?? s.today.last
    }

    private func details(_ session: WidgetSnapshot.Session) -> String {
        var parts = ["\(session.durationMin) min"]
        if let km = session.distanceKm { parts.append(Fmt.km(km * 1000, decimals: 1) + " km") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func sessionBlock(_ s: WidgetSnapshot) -> some View {
        if let session = main(s) {
            Label(session.kind.label, systemImage: session.done ? "checkmark.circle.fill" : "figure.run")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rc.accentText)
            Text(session.title)
                .font(.headline)
                .lineLimit(2)
            Text(session.done ? "Fait" : details(session))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Label("Repos", systemImage: "moon.zzz.fill")
                .font(.headline)
            if let next = s.next {
                Text("Ensuite : \(next.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sessionBlock(s)
            Spacer(minLength: 0)
            ProgressView(value: s.weekProgress)
                .tint(Color.rc.accent)
            Text("\(Fmt.km(s.weekDoneKm * 1000, decimals: 0)) / \(Fmt.km(s.weekPlannedKm * 1000, decimals: 0)) km")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                sessionBlock(s)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                Circle().stroke(Color.rc.surfaceRaised, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: s.weekProgress)
                    .stroke(Color.rc.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(Fmt.km(s.weekDoneKm * 1000, decimals: 0))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("/ \(Fmt.km(s.weekPlannedKm * 1000, decimals: 0)) km")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)
        }
    }

    private func ring(_ s: WidgetSnapshot) -> some View {
        Gauge(value: s.weekProgress) {
            Image(systemName: "figure.run")
        } currentValueLabel: {
            Text(Fmt.km(s.weekDoneKm * 1000, decimals: 0))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private func lockLine(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let session = main(s) {
                Text(session.title).font(.headline).lineLimit(1)
                Text(session.done ? "Fait" : details(session)).font(.caption)
            } else {
                Text("Repos").font(.headline)
                if let next = s.next { Text("Ensuite : \(next.title)").font(.caption).lineLimit(1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
