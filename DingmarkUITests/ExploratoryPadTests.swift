import XCTest

/// Exploratory pass over the iPad split view (demo, French, light). Skipped
/// on a phone.
final class ExploratoryPadTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only")
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR", "-UIUserInterfaceStyle", "Light"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(row("Tailscale SSH").waitForExistence(timeout: 15), "list did not load")
    }

    private func row(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// A row of the content list only (the detail column repeats the title).
    private func listRow(_ text: String) -> XCUIElement {
        app.cells.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func text(_ contains: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", contains)).firstMatch
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dump(_ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func expectGone(_ element: XCUIElement, _ message: String, timeout: TimeInterval = 4) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    func test01_SplitViewNavigation() {
        dump("pad-01-hierarchy")
        shot("pad-01-liste")
        XCTAssertTrue(app.staticTexts["Sélectionnez un favori"].exists, "detail placeholder missing")
        let sidebarUnread = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Non lus'")).firstMatch
        XCTAssertTrue(sidebarUnread.exists, "sidebar filter missing")
        print("SIDEBAR:", app.cells.allElementsBoundByIndex.map(\.label).prefix(20))

        sidebarUnread.tap()
        XCTAssertTrue(row("Focaccia").waitForExistence(timeout: 3))
        expectGone(row("Adopting Liquid Glass"), "read bookmark listed under Non lus")
        shot("pad-01-non-lus")

        let sidebarTag = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'selfhosting'")).firstMatch
        XCTAssertTrue(sidebarTag.exists, "sidebar tag missing")
        sidebarTag.tap()
        XCTAssertTrue(app.navigationBars["selfhosting"].waitForExistence(timeout: 3), "list title should be the tag")
        XCTAssertTrue(row("Restic").exists)
        expectGone(row("Focaccia"), "tag filter did not apply")
        shot("pad-01-tag")

        row("Tailscale SSH").tap()
        XCTAssertTrue(app.buttons["Ouvrir"].firstMatch.waitForExistence(timeout: 5), "detail column empty")
        XCTAssertTrue(text("Remplacer les clés sur le NAS").exists)
        shot("pad-01-detail")

        // Tag chip in the detail switches the filter; the detail stays.
        app.buttons["réseau"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["réseau"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Ouvrir"].firstMatch.exists, "detail should stay visible on iPad")
        shot("pad-01-detail-tag")

        let sidebarAll = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Tous'")).firstMatch
        sidebarAll.tap()
        XCTAssertTrue(app.navigationBars["Favoris"].waitForExistence(timeout: 3))

        // Search in the content column.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("immich")
        XCTAssertTrue(row("Immich").waitForExistence(timeout: 3))
        expectGone(listRow("Tailscale SSH"), "search did not filter")
        shot("pad-01-recherche")
        let cancel = app.buttons["Annuler"].firstMatch
        if cancel.exists { cancel.tap() } else { search.buttons["Effacer le texte"].firstMatch.tap() }

        // Add from the sidebar toolbar, settings from the bottom bar.
        app.buttons["Ajouter un favori"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Nouveau favori"].waitForExistence(timeout: 5), "add sheet missing")
        shot("pad-01-ajout")
        app.buttons["Annuler"].firstMatch.tap()

        app.buttons["Réglages"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Réglages"].waitForExistence(timeout: 5), "settings sheet missing")
        XCTAssertTrue(text("Démonstration · 9 favoris").exists)
        shot("pad-01-reglages")
        app.buttons["OK"].firstMatch.tap()
        expectGone(app.navigationBars["Réglages"], "settings sheet did not close")

        // Delete the selected bookmark from the detail menu: the detail must empty.
        // Kiln sits below the fold: bring it up with the search.
        search.tap()
        search.typeText("Kiln")
        XCTAssertTrue(row("Kiln").waitForExistence(timeout: 5), "search for Kiln failed")
        row("Kiln").tap()
        XCTAssertTrue(text("Kiln — Mastering ambient guitar loops").waitForExistence(timeout: 5))
        app.buttons["Plus d’actions"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Supprimer"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Supprimer"].firstMatch.tap()
        expectGone(listRow("Kiln"), "deleted row still listed")
        XCTAssertTrue(app.staticTexts["Sélectionnez un favori"].waitForExistence(timeout: 5), "detail should reset after deleting the selection")
        shot("pad-01-apres-suppression")
        app.buttons["Effacer la recherche"].firstMatch.tap()
        if app.buttons["Annuler"].firstMatch.exists { app.buttons["Annuler"].firstMatch.tap() }

        // Deep link selects the bookmark.
        app.open(URL(string: "dingmark://bookmark/3")!)
        XCTAssertTrue(text("Adopting Liquid Glass").waitForExistence(timeout: 5), "deep link did not select the bookmark")
        XCTAssertTrue(app.buttons["Ouvrir"].firstMatch.exists)
        shot("pad-01-deeplink")

        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        shot("pad-01-portrait")
        XCTAssertTrue(row("Tailscale SSH").waitForExistence(timeout: 5), "list missing in portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
    }
}
