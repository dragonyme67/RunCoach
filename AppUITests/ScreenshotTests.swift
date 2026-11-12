import XCTest

/// Capture chaque écran en clair et en sombre. Les images sortent en pièces jointes du résultat de test ;
/// la CI les exporte dans l'artefact `screenshots`.
/// Un test par apparence : si le simulateur se bloque, la CI ne relance que la moitié concernée.
final class ScreenshotTests: XCTestCase {
    private let screens = [
        "today", "plan", "planned", "strength", "run", "replay", "replaymap", "coach", "progress", "settings", "onboarding"
    ]

    /// Ouvrir une sortie doit afficher son détail, depuis l'accueil comme depuis la liste de l'onglet Progrès
    /// (bug vu sur iPhone : la liste se rouvrait à la place du détail).
    func testOpenRunShowsItsDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "tabs"]
        app.launch()
        let replay = app.buttons["Rejouer"]

        app.buttons["run-row"].firstMatch.tap()
        XCTAssertTrue(replay.waitForExistence(timeout: 10), "Accueil : le détail de la sortie ne s'ouvre pas")

        app.tabBars.buttons["Progrès"].tap()
        let allRuns = app.buttons["all-runs"]
        XCTAssertTrue(allRuns.waitForExistence(timeout: 10))
        for _ in 0..<6 where !allRuns.isHittable {
            app.swipeUp()
        }
        allRuns.tap()
        let row = app.buttons["run-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "La liste des sorties ne s'ouvre pas")
        row.tap()
        XCTAssertTrue(replay.waitForExistence(timeout: 10), "Liste : le détail de la sortie ne s'ouvre pas")
    }

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
            // Écrans longs : captures supplémentaires en faisant défiler, pour voir les graphiques du bas.
            for page in 0..<(["run": 3, "progress": 2][screen] ?? 0) {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1.5)
                let more = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                more.name = "\(screen)\(page + 2)-\(scheme)"
                more.lifetime = .keepAlways
                add(more)
            }
            app.terminate()
        }
    }
}
