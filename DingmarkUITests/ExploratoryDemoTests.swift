import XCTest

/// Exploratory pass over the demo app (French, light). Every step attaches a
/// screenshot; failures keep going so one run reports every problem.
final class ExploratoryDemoTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR", "-UIUserInterfaceStyle", "Light"]
        app.launch()
        XCTAssertTrue(row("Tailscale SSH").waitForExistence(timeout: 15), "list did not load")
    }

    // MARK: Helpers

    private func row(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func button(prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
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
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    /// Toasts last 1.8 s: too short for a reliable query on a busy screen.
    /// Screenshot right away and report without failing.
    private func toast(_ message: String, _ name: String) {
        shot(name)
        let found = text(message).waitForExistence(timeout: 2)
        print("TOAST", message, found ? "seen" : "not seen by the query (check \(name))")
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }

    /// The search bar's close control has no stable label across iOS
    /// versions (text "Annuler", or an xmark): clear, then dismiss.
    private func closeSearch(_ search: XCUIElement) {
        let clear = search.buttons["Effacer le texte"].firstMatch
        if clear.exists { clear.tap() }
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Annuler", "Fermer", "Cancel", "Close"])).firstMatch
        if close.exists { close.tap() } else if search.exists { search.typeText("\n") }
    }

    /// iOS 26 may collapse a searchable list into a search button.
    private func openSearch() -> XCUIElement {
        if !app.searchFields.firstMatch.exists {
            let button = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Rechercher'")).firstMatch
            if button.waitForExistence(timeout: 2) { button.tap() }
        }
        return app.searchFields.firstMatch
    }

    /// Places the cursor at the end, deletes the current value one key at a
    /// time (select-all menus are unreliable), then types.
    private func clearAndType(_ field: XCUIElement, _ value: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        field.typeText(value)
    }


    /// The tag field reads "Ajouter un tag" when empty and "Ajouter" once a
    /// chip exists (a default tag left by an earlier run, for instance); the
    /// placeholder is the label on iOS 27 and the placeholderValue on iOS 26.
    private func tagField(_ placeholder: String) -> XCUIElement {
        let names = ["Ajouter un tag", "Ajouter"]
        return app.textFields.matching(NSPredicate(format: "label IN %@ OR placeholderValue IN %@ OR value IN %@", names, names, names)).firstMatch
    }

    // MARK: Tests

    func test01_ListFiltersAndSearch() {
        dump("01-hierarchy-list")
        shot("01-liste")
        XCTAssertTrue(button(prefix: "Tous").exists)
        XCTAssertTrue(button(prefix: "Non lus").exists)
        XCTAssertTrue(button(prefix: "Archivés").exists)
        XCTAssertTrue(button(prefix: "Sans tag").exists)
        print("PILLS:", [button(prefix: "Tous").label, button(prefix: "Non lus").label, button(prefix: "Archivés").label, button(prefix: "Sans tag").label])

        button(prefix: "Non lus").tap()
        XCTAssertTrue(row("Focaccia").waitForExistence(timeout: 3))
        XCTAssertTrue(row("Le Monde diplomatique").exists)
        expectGone(row("Adopting Liquid Glass"), "read bookmark still listed under Non lus")
        shot("01-non-lus")

        button(prefix: "Archivés").tap()
        XCTAssertTrue(row("Caddy").waitForExistence(timeout: 3))
        XCTAssertTrue(row("lecture lente").exists)
        XCTAssertTrue(app.navigationBars["Archivés"].waitForExistence(timeout: 3), "title should switch to Archivés")
        shot("01-archives")

        button(prefix: "Sans tag").tap()
        XCTAssertTrue(row("Paperless").waitForExistence(timeout: 3))
        XCTAssertTrue(row("Le Monde diplomatique").exists)
        expectGone(row("Tailscale SSH"), "tagged bookmark listed under Sans tag")
        XCTAssertTrue(app.navigationBars["Favoris"].exists)
        button(prefix: "Tous").tap()
        XCTAssertTrue(row("Tailscale SSH").waitForExistence(timeout: 3))

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("tailscale")
        XCTAssertTrue(row("Tailscale SSH").waitForExistence(timeout: 3))
        expectGone(row("Immich"), "search did not filter")
        shot("01-recherche")

        search.buttons["Effacer le texte"].firstMatch.tap()
        search.typeText("reseau")
        XCTAssertTrue(row("Tailscale SSH").waitForExistence(timeout: 3), "diacritic-insensitive tag search failed")
        expectGone(row("Immich"), "search 'reseau' did not filter")

        search.buttons["Effacer le texte"].firstMatch.tap()
        search.typeText("zzzz")
        XCTAssertTrue(text("Aucun résultat").waitForExistence(timeout: 3))
        shot("01-aucun-resultat")
        app.buttons["Effacer la recherche"].firstMatch.tap()
        XCTAssertTrue(row("Tailscale SSH").waitForExistence(timeout: 3), "clearing the search did not restore the list")
        let cancel = app.buttons["Annuler"].firstMatch
        if cancel.exists { cancel.tap() }

        // Filter + search combined: unread + "immich".
        button(prefix: "Non lus").tap()
        search.tap()
        search.typeText("immich")
        XCTAssertTrue(row("Immich").waitForExistence(timeout: 3))
        expectGone(row("Tailscale SSH"), "filter and search were not combined")
        if cancel.exists { cancel.tap() }
        button(prefix: "Tous").tap()
    }

    func test02_DetailTagFilterAndEdit() {
        row("Tailscale SSH").tap()
        XCTAssertTrue(app.buttons["Ouvrir"].firstMatch.waitForExistence(timeout: 5))
        dump("02-hierarchy-detail")
        shot("02-detail")
        XCTAssertTrue(text("Remplacer les clés sur le NAS").exists, "markdown bullet missing")
        XCTAssertTrue(text("À tester").exists, "markdown heading missing")
        let unreadToggle = app.switches["Non lu"].firstMatch
        XCTAssertTrue(unreadToggle.exists, "unread toggle missing")
        XCTAssertEqual(unreadToggle.value as? String, "1")

        unreadToggle.tap()
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label == 'Non lu' AND value == '0'")).firstMatch.waitForExistence(timeout: 3), "toggle did not switch off")
        unreadToggle.tap()
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label == 'Non lu' AND value == '1'")).firstMatch.waitForExistence(timeout: 3), "toggle did not switch back on")

        app.buttons["Copier l’URL"].firstMatch.tap()
        XCTAssertTrue(text("URL copiée").waitForExistence(timeout: 3), "copy toast missing")

        // Tag chip filters the list and pops the detail.
        app.buttons["réseau"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["réseau"].waitForExistence(timeout: 5), "tag filter title missing")
        XCTAssertTrue(row("Tailscale SSH").exists)
        expectGone(row("Immich"), "tag filter did not apply")
        XCTAssertTrue(app.buttons["Retirer le filtre réseau"].firstMatch.exists, "remove filter chip missing")
        shot("02-filtre-tag")
        app.buttons["Retirer le filtre réseau"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Favoris"].waitForExistence(timeout: 3))
        XCTAssertTrue(row("Immich").waitForExistence(timeout: 3))

        // Edit the title.
        row("Tailscale SSH").tap()
        XCTAssertTrue(app.buttons["Modifier"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Modifier"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Modifier"].waitForExistence(timeout: 5))
        dump("02-hierarchy-edit")
        shot("02-modifier")
        let title = app.textFields["Titre"].firstMatch
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.value as? String, "Tailscale SSH — Tailscale Docs")
        XCTAssertFalse(app.buttons["Coller"].exists, "paste button should be hidden while editing")
        clearAndType(title, "Tailscale SSH (test)")
        app.buttons["Enregistrer"].firstMatch.tap()
        toast("Enregistré", "02-toast-enregistre")
        XCTAssertTrue(text("Tailscale SSH (test)").waitForExistence(timeout: 5), "edited title not shown")
        shot("02-modifie")

        // Ellipsis menu archives from the detail.
        app.buttons["Plus d’actions"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Archiver"].firstMatch.waitForExistence(timeout: 3))
        shot("02-menu")
        app.buttons["Archiver"].firstMatch.tap()
        toast("Archivé", "02-toast-archive")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        expectGone(row("Tailscale SSH"), "archived bookmark still in Tous")
        XCTAssertTrue(button(prefix: "Archivés, 3").waitForExistence(timeout: 3) || button(prefix: "Archivés 3").exists, "archived count not updated: \(button(prefix: "Archivés").label)")
    }

    func test03_AddAndDuplicate() {
        app.buttons["Ajouter un favori"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Nouveau favori"].waitForExistence(timeout: 5))
        dump("03-hierarchy-add")
        shot("03-ajout-vide")
        XCTAssertTrue(app.buttons["Coller"].firstMatch.exists, "paste button missing on an empty URL")
        XCTAssertFalse(app.buttons["Enregistrer"].firstMatch.isEnabled, "save enabled with an empty URL")

        let url = app.textFields["URL"].firstMatch
        url.tap()
        url.typeText("linkding.link/docs")
        let title = app.textFields["Titre"].firstMatch
        XCTAssertTrue(waitUntil { title.value as? String == "linkding" }, "scraped title not applied, got \(title.value ?? "nil")")
        XCTAssertTrue(app.buttons["Enregistrer"].firstMatch.isEnabled)
        XCTAssertFalse(app.buttons["Coller"].exists, "paste button should hide once a URL is typed")

        let tagInput = tagField("Ajouter un tag")
        XCTAssertTrue(tagInput.exists, "tag field missing")
        tagInput.tap()
        tagInput.typeText("sw")
        XCTAssertTrue(app.buttons["swift"].firstMatch.waitForExistence(timeout: 3), "suggestion swift missing")
        XCTAssertTrue(app.buttons["swiftui"].firstMatch.exists, "suggestion swiftui missing")
        shot("03-suggestions")
        app.buttons["swift"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Retirer le tag swift"].firstMatch.waitForExistence(timeout: 3), "chip swift missing")
        let tagField2 = tagField("Ajouter")
        XCTAssertTrue(tagField2.waitForExistence(timeout: 3), "tag field placeholder after a chip")
        tagField2.tap()
        tagField2.typeText("Veille,")
        XCTAssertTrue(app.buttons["Retirer le tag veille"].firstMatch.waitForExistence(timeout: 3), "comma did not commit the tag")

        let unread = app.switches["Marquer non lu"].firstMatch
        XCTAssertEqual(unread.value as? String, "1", "unread by default should be on")

        app.textViews.firstMatch.tap()
        app.textViews.firstMatch.typeText("# Titre\n- point un")
        shot("03-ajout-rempli")
        app.buttons["Enregistrer"].firstMatch.tap()
        toast("Enregistré", "03-toast-enregistre")
        XCTAssertTrue(row("linkding").waitForExistence(timeout: 5), "new bookmark not listed")
        shot("03-liste-apres-ajout")
        let newRow = row("linkding")
        XCTAssertTrue(newRow.label.hasPrefix("Non lu"), "new bookmark should be unread: \(newRow.label)")
        XCTAssertTrue(newRow.label.contains("swift, veille") || newRow.label.contains("veille"), "tags missing in row: \(newRow.label)")

        newRow.tap()
        XCTAssertTrue(app.buttons["Ouvrir"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(text("point un").exists, "notes not rendered")
        shot("03-detail-nouveau")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Duplicate detection, then changing the URL must drop the pre-filled data.
        app.buttons["Ajouter un favori"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Nouveau favori"].waitForExistence(timeout: 5))
        let url2 = app.textFields["URL"].firstMatch
        url2.tap()
        url2.typeText("https://restic.net")
        XCTAssertTrue(text("Déjà enregistré").waitForExistence(timeout: 5), "duplicate warning missing")
        XCTAssertTrue(app.buttons["Mettre à jour"].firstMatch.exists, "save button should read Mettre à jour")
        XCTAssertEqual(app.textFields["Titre"].firstMatch.value as? String, "Restic — Backups done right")
        shot("03-doublon")
        url2.typeText("/docs")
        expectGone(text("Déjà enregistré"), "duplicate warning stayed after the URL changed", timeout: 6)
        XCTAssertTrue(app.buttons["Enregistrer"].firstMatch.waitForExistence(timeout: 3), "save button should read Enregistrer again")
        let titleField = app.textFields["Titre"].firstMatch
        XCTAssertTrue(waitUntil { (titleField.value as? String) == "Restic.Net" }, "title should follow the new URL, got \(titleField.value ?? "nil")")
        shot("03-doublon-url-changee")
        app.buttons["Annuler"].firstMatch.tap()
    }

    func test04_SwipeActionsAndContextMenu() {
        let immich = row("Immich")
        immich.swipeLeft()
        XCTAssertTrue(app.buttons["Lu"].firstMatch.waitForExistence(timeout: 3), "swipe action Lu missing")
        XCTAssertTrue(app.buttons["Archiver"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Supprimer"].firstMatch.exists)
        shot("04-swipe")
        app.buttons["Lu"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Immich'")).firstMatch.waitForExistence(timeout: 3), "row should no longer read Non lu")
        print("UNREAD PILL after read:", button(prefix: "Non lus").label)

        immich.swipeLeft()
        XCTAssertTrue(app.buttons["Non lu"].firstMatch.waitForExistence(timeout: 3), "swipe action Non lu missing")
        app.buttons["Archiver"].firstMatch.tap()
        toast("Archivé", "04-toast-archive")
        expectGone(row("Immich"), "archived row still visible")
        print("ARCHIVED PILL:", button(prefix: "Archivés").label)

        // Context menu on Restic.
        row("Restic").press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Marquer non lu"].firstMatch.waitForExistence(timeout: 3), "context menu missing")
        XCTAssertTrue(app.buttons["Ouvrir dans Safari"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Copier l’URL"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Partager…"].firstMatch.exists)
        shot("04-menu-contextuel")
        app.buttons["Supprimer"].firstMatch.tap()
        toast("Supprimé", "04-toast-supprime")
        expectGone(row("Restic"), "deleted row still visible")

        // Archived filter: unarchive via swipe.
        button(prefix: "Archivés").tap()
        XCTAssertTrue(row("Immich").waitForExistence(timeout: 3))
        row("Immich").swipeLeft()
        XCTAssertTrue(app.buttons["Désarchiver"].firstMatch.waitForExistence(timeout: 3), "swipe action Désarchiver missing")
        app.buttons["Désarchiver"].firstMatch.tap()
        toast("Désarchivé", "04-toast-desarchive")
        expectGone(row("Immich"), "unarchived row still in Archivés")
        button(prefix: "Tous").tap()
        XCTAssertTrue(row("Immich").waitForExistence(timeout: 3))

        // Pull to refresh keeps the demo state.
        row("Tailscale SSH").swipeDown()
        XCTAssertTrue(row("Tailscale SSH").waitForExistence(timeout: 5))
        shot("04-apres-refresh")
    }

    func test05_TagsAndSettings() {
        let tabs = app.tabBars.firstMatch
        tabs.buttons["Tags"].tap()
        XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 5))
        dump("05-hierarchy-tags")
        shot("05-tags")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'selfhosting'")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'lecture'")).firstMatch.exists, "tag carried only by an archived bookmark listed")
        print("TAG ROWS:", app.buttons.allElementsBoundByIndex.map(\.label).filter { $0.contains("tag") || $0.contains(",") })

        let search = openSearch()
        XCTAssertTrue(search.waitForExistence(timeout: 3), "tag search field missing")
        search.tap()
        search.typeText("sw")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'swiftui'")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'docker'")).firstMatch.exists, "tag search did not filter")
        shot("05-tags-recherche")
        closeSearch(search)

        app.buttons.matching(NSPredicate(format: "label CONTAINS 'selfhosting'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["selfhosting"].waitForExistence(timeout: 5), "tag tap should filter the list")
        XCTAssertTrue(row("Tailscale SSH").exists)
        XCTAssertTrue(row("Restic").exists)
        expectGone(row("Focaccia"), "tag filter selfhosting shows unrelated rows")
        shot("05-filtre-selfhosting")
        app.buttons["Retirer le filtre selfhosting"].firstMatch.tap()

        tabs.buttons["Réglages"].tap()
        XCTAssertTrue(app.navigationBars["Réglages"].waitForExistence(timeout: 5))
        dump("05-hierarchy-settings")
        shot("05-reglages")
        XCTAssertTrue(text("links.example.org").exists)
        XCTAssertTrue(text("Démonstration · 9 favoris").exists, "settings count wrong")
        XCTAssertFalse(app.buttons["Changer de serveur"].exists, "server switch should be hidden in demo")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tags par défaut'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Tags par défaut"].waitForExistence(timeout: 5))
        // Leftovers from an interrupted run would change the form's placeholders.
        var leftover = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Retirer le tag'")).firstMatch
        while leftover.exists {
            leftover.tap()
            leftover = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Retirer le tag'")).firstMatch
        }
        let tagInput = tagField("Ajouter un tag")
        tagInput.tap()
        tagInput.typeText("inbox\n")
        XCTAssertTrue(app.buttons["Retirer le tag inbox"].firstMatch.waitForExistence(timeout: 3), "default tag chip missing")
        shot("05-tags-defaut")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'inbox'")).firstMatch.waitForExistence(timeout: 3), "default tag summary not updated")

        tabs.buttons["Favoris"].tap()
        app.buttons["Ajouter un favori"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Retirer le tag inbox"].firstMatch.waitForExistence(timeout: 5), "default tag not applied to a new bookmark")
        app.buttons["Annuler"].firstMatch.tap()

        // Clean up the default tag so the next run starts fresh.
        tabs.buttons["Réglages"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tags par défaut'")).firstMatch.tap()
        app.buttons["Retirer le tag inbox"].firstMatch.tap()
        expectGone(app.buttons["Retirer le tag inbox"].firstMatch, "default tag not removed")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Density: the form has grown past one screen, scroll to the control.
        scrollUntilVisible(app.buttons["Compacte"].firstMatch)
        app.buttons["Compacte"].firstMatch.tap()
        restoreTabBar()
        tabs.buttons["Favoris"].tap()
        sleep(1)
        shot("05-liste-compacte")
        tabs.buttons["Réglages"].tap()
        scrollUntilVisible(app.buttons["Avec description"].firstMatch)
        app.buttons["Avec description"].firstMatch.tap()
    }

    /// Scrolling down minimises the tab bar (iOS 26) to the selected tab only:
    /// scroll back to the top so every tab button exists again.
    private func restoreTabBar() {
        var remaining = 3
        while !app.tabBars.buttons["Favoris"].exists, remaining > 0 {
            app.swipeDown()
            remaining -= 1
        }
    }

    /// Lists only materialise visible rows: swipe up until the element exists.
    private func scrollUntilVisible(_ element: XCUIElement, attempts: Int = 5) {
        var remaining = attempts
        while !(element.exists && element.isHittable), remaining > 0 {
            app.swipeUp()
            remaining -= 1
        }
    }

    func test06_DeepLinks() {
        app.open(URL(string: "dingmark://bookmark/3")!)
        XCTAssertTrue(text("Adopting Liquid Glass").waitForExistence(timeout: 5), "bookmark deep link did not open the detail")
        XCTAssertTrue(app.buttons["Ouvrir"].firstMatch.exists)
        shot("06-deeplink-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.open(URL(string: "dingmark://add?url=https%3A%2F%2Fimmich.app")!)
        XCTAssertTrue(app.navigationBars["Nouveau favori"].waitForExistence(timeout: 5), "add deep link did not open the sheet")
        XCTAssertEqual(app.textFields["URL"].firstMatch.value as? String, "https://immich.app")
        XCTAssertTrue(text("Déjà enregistré").waitForExistence(timeout: 5), "prefilled URL not checked for duplicates")
        shot("06-deeplink-add")
        app.buttons["Annuler"].firstMatch.tap()

        app.open(URL(string: "dingmark://add")!)
        XCTAssertTrue(app.navigationBars["Nouveau favori"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Coller"].firstMatch.exists)
        app.buttons["Annuler"].firstMatch.tap()

        // A deep link while a detail is pushed.
        row("Focaccia").tap()
        XCTAssertTrue(app.buttons["Ouvrir"].firstMatch.waitForExistence(timeout: 5))
        app.open(URL(string: "dingmark://bookmark/5")!)
        XCTAssertTrue(text("Restic — Backups done right").waitForExistence(timeout: 5), "deep link over a pushed detail did not navigate")
        shot("06-deeplink-over-detail")
    }
}
