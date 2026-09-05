import XCTest

/// Drives the demo app through every screen and attaches a screenshot of
/// each one. Not assertions on pixels: a visual record to review after a
/// change (see README, "captures").
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testLightFrench() throws {
        try runDemoFlow(appearance: .light, language: "fr", prefix: "fr-light")
    }

    func testDarkFrench() throws {
        try runDemoFlow(appearance: .dark, language: "fr", prefix: "fr-dark")
    }

    func testLightEnglish() throws {
        try runDemoFlow(appearance: .light, language: "en", prefix: "en-light")
    }

    func testLoginScreen() throws {
        XCUIDevice.shared.appearance = .light
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR", "-skipDemo"]
        app.launch()
        XCTAssertTrue(app.buttons["Tester la connexion"].waitForExistence(timeout: 10))
        shot("fr-light-00-connexion")
    }

    private func runDemoFlow(appearance: XCUIDevice.Appearance, language: String, prefix: String) throws {
        XCUIDevice.shared.appearance = appearance
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "fr" ? "fr_FR" : "en_US",
                               // The simulator does not always honour XCUIDevice.appearance: force it on the app.
                               "-UIUserInterfaceStyle", appearance == .dark ? "Dark" : "Light"]
        app.launch()

        // Rows are single accessibility elements (children combined): match on the label.
        let firstRow = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Tailscale SSH")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15), "list did not load")
        sleep(1)
        shot("\(prefix)-01-liste")

        let isPad = app.tabBars.count == 0
        if isPad {
            firstRow.tap()
            XCTAssertTrue(app.buttons[language == "fr" ? "Ouvrir" : "Open"].firstMatch.waitForExistence(timeout: 5))
            sleep(1)
            shot("\(prefix)-02-ipad-detail")
            return
        }

        firstRow.tap()
        XCTAssertTrue(app.buttons[language == "fr" ? "Ouvrir" : "Open"].firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        shot("\(prefix)-02-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let unreadFilter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", language == "fr" ? "Non lus" : "Unread")).firstMatch
        if unreadFilter.waitForExistence(timeout: 5) {
            unreadFilter.tap()
            sleep(1)
            shot("\(prefix)-03-non-lus")
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", language == "fr" ? "Tous" : "All")).firstMatch.tap()
        }

        let tabs = app.tabBars.firstMatch
        tabs.buttons[language == "fr" ? "Tags" : "Tags"].tap()
        sleep(1)
        shot("\(prefix)-04-tags")

        tabs.buttons[language == "fr" ? "Réglages" : "Settings"].tap()
        sleep(1)
        shot("\(prefix)-05-reglages")

        tabs.buttons[language == "fr" ? "Favoris" : "Bookmarks"].tap()
        let add = app.buttons[language == "fr" ? "Ajouter un favori" : "Add Bookmark"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.staticTexts[language == "fr" ? "Nouveau favori" : "New Bookmark"].waitForExistence(timeout: 5))
        sleep(1)
        shot("\(prefix)-06-ajout")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
