import SwiftUI
import SwiftData

@main
struct RunCoachApp: App {
    private let container: ModelContainer
    private let options: LaunchOptions

    init() {
        container = AppEnvironment.makeContainer()
        options = LaunchOptions.current
    }

    var body: some Scene {
        WindowGroup {
            RootView(options: options)
                .preferredColorScheme(options.colorScheme)
                .tint(Color.rc.accentText)
                // Interface en français quelle que soit la langue du téléphone (dates, graphiques, sélecteurs).
                .environment(\.locale, Locale(identifier: "fr_FR"))
        }
        .modelContainer(container)
    }
}
