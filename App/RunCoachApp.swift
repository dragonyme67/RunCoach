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
        }
        .modelContainer(container)
    }
}
