import XCTest

/// Capture chaque écran en clair et en sombre. Les images sortent en pièces jointes du résultat de test ;
/// la CI les exporte dans l'artefact `screenshots`.
/// Un test par apparence : si le simulateur se bloque, la CI ne relance que la moitié concernée.
final class ScreenshotTests: XCTestCase {
    private let screens = [
        "today", "plan", "planned", "strength", "run", "replay", "replayflat", "coach", "progress", "settings", "onboarding"
    ]

    func testCaptureDark() {
        capture(scheme: "dark")
    }

    func testCaptureLight() {
        capture(scheme: "light")
    }

    private func capture(scheme: String) {
        continueAfterFailure = true
        for screen in screens {
            let app = XCUIApplication()
            app.launchArguments = ["-screen", screen, "-scheme", scheme]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "\(screen) ne démarre pas")
            // Laisse le temps aux données factices, aux graphiques et à la carte de s'afficher.
            Thread.sleep(forTimeInterval: screen.hasPrefix("replay") || screen == "run" ? 5 : 1.5)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "\(screen)-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
