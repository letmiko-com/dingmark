import XCTest

/// Runs against a throwaway linkding reachable from the simulator. The
/// server and the token come from the environment of the test runner
/// (`TEST_RUNNER_DINGMARK_TEST_SERVER`, `TEST_RUNNER_DINGMARK_TEST_TOKEN`);
/// the whole class is skipped when they are missing. Tests are ordered by
/// name: 01 logs in, 05 signs out.
final class RealServerTests: XCTestCase {
    private var app: XCUIApplication!
    private var server = ""
    private var token = ""

    override func setUpWithError() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        server = env["DINGMARK_TEST_SERVER"] ?? ""
        token = env["DINGMARK_TEST_TOKEN"] ?? ""
        try XCTSkipIf(server.isEmpty || token.isEmpty, "no test server configured")
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR", "-UIUserInterfaceStyle", "Light"]
        app.launch()
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

    private func shot(_ name: String, of application: XCUIApplication? = nil) {
        let attachment = XCTAttachment(screenshot: (application ?? app).screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dump(_ name: String, of application: XCUIApplication? = nil) {
        let attachment = XCTAttachment(string: (application ?? app).debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func expectGone(_ element: XCUIElement, _ message: String, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    /// Newest bookmark of the seed, always at the top of the list: XCUITest
    /// only sees the cells on screen.
    private var connectedMarker: XCUIElement { row("Site 122") }

    private func closeSearch(_ search: XCUIElement) {
        let clear = search.buttons["Effacer le texte"].firstMatch
        if clear.exists { clear.tap() }
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Annuler", "Fermer", "Cancel", "Close"])).firstMatch
        if close.exists { close.tap() } else if search.exists { search.typeText("\n") }
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

    /// Direct API call from the test runner to verify the server state.
    private func api(_ method: String, _ path: String, body: [String: Any]? = nil) -> (Int, [String: Any]) {
        var request = URLRequest(url: URL(string: server + path)!)
        request.httpMethod = method
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var status = 0
        var json: [String: Any] = [:]
        URLSession.shared.dataTask(with: request) { data, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data, let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { json = parsed }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return (status, json)
    }

    private func serverBookmarks(matching query: String, archived: Bool = false) -> [[String: Any]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        let (_, json) = api("GET", "/api/bookmarks/\(archived ? "archived/" : "")?q=\(encoded)&limit=50")
        return json["results"] as? [[String: Any]] ?? []
    }


    /// The tag field exposes its placeholder as label on iOS 27 and as
    /// placeholderValue on iOS 26: match both.
    private func tagField(_ placeholder: String) -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "label == %@ OR placeholderValue == %@ OR value == %@", placeholder, placeholder, placeholder)).firstMatch
    }

    // MARK: Tests

    func test01_LoginErrorsThenConnect() {
        let test = app.buttons["Tester la connexion"].firstMatch
        XCTAssertTrue(test.waitForExistence(timeout: 10), "login screen missing")
        dump("01-hierarchy-login")
        shot("01-connexion")
        XCTAssertFalse(test.isEnabled, "test button enabled with empty fields")

        let serverField = app.textFields["links.example.org"].firstMatch
        let tokenField = app.secureTextFields.firstMatch
        XCTAssertTrue(serverField.exists && tokenField.exists)

        // Bare host of a plain-HTTP server: https is assumed, the handshake fails.
        let host = server.replacingOccurrences(of: "http://", with: "")
        serverField.tap()
        serverField.typeText(host)
        tokenField.tap()
        tokenField.typeText("wrong-token")
        shot("01-jeton-en-saisie")
        print("TOKEN FIELD VALUE:", tokenField.value ?? "nil")
        XCTAssertTrue(test.isEnabled)
        test.tap()
        let card = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Serveur injoignable", "Certificat non reconnu", "Jeton refusé", "URL invalide"])).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "no error card for a bare host")
        print("LOGIN ERROR (bare host, https assumed):", card.label)
        shot("01-erreur-https")

        // Explicit http and a wrong token: 401.
        clearAndType(serverField, server)
        test.tap()
        XCTAssertTrue(app.staticTexts["Jeton refusé"].waitForExistence(timeout: 20), "401 not reported as Jeton refusé")
        XCTAssertTrue(text("401").exists)
        shot("01-erreur-jeton")

        clearAndType(tokenField, token)
        test.tap()
        XCTAssertTrue(connectedMarker.waitForExistence(timeout: 30), "list did not load after login")
        let passwordPrompt = app.staticTexts["Enregistrer le mot de passe ?"].firstMatch
        if passwordPrompt.waitForExistence(timeout: 3) {
            shot("01-prompt-mot-de-passe")
            XCTFail("iOS offered to save the API token as a password")
            app.buttons["Plus tard"].firstMatch.tap()
        }
        print("PILLS:", [button(prefix: "Tous").label, button(prefix: "Non lus").label, button(prefix: "Archivés").label, button(prefix: "Sans tag").label])
        XCTAssertTrue(button(prefix: "Tous, 120").exists || button(prefix: "Tous 120").exists, "active count: \(button(prefix: "Tous").label)")
        XCTAssertTrue(button(prefix: "Archivés, 10").exists || button(prefix: "Archivés 10").exists, "archived count: \(button(prefix: "Archivés").label)")
        shot("01-liste-reelle")
    }

    func test02_RealDataListDetailSettings() {
        XCTAssertTrue(connectedMarker.waitForExistence(timeout: 30), "not connected")
        dump("02-hierarchy-list")
        shot("02-liste")
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("no-title")
        // The seed left the title empty; linkding scraped "Example Domain" as website title, which the row shows.
        XCTAssertTrue(row("example.com/no-title").waitForExistence(timeout: 5) || row("Example Domain").waitForExistence(timeout: 2), "untitled bookmark should show its scraped title or URL")
        shot("02-sans-titre")
        search.buttons["Effacer le texte"].firstMatch.tap()
        search.typeText("extrêmement")
        XCTAssertTrue(row("agrandi").waitForExistence(timeout: 5), "long title truncated in the row label")
        shot("02-titre-long")
        search.buttons["Effacer le texte"].firstMatch.tap()
        search.typeText("Site 001")
        XCTAssertTrue(row("Site 001").waitForExistence(timeout: 5), "bookmark from the second page missing (pagination)")
        search.buttons["Effacer le texte"].firstMatch.tap()
        search.typeText("Site 122")
        XCTAssertTrue(row("Site 122").waitForExistence(timeout: 5))
        closeSearch(search)

        button(prefix: "Archivés").tap()
        XCTAssertTrue(row("Site 120").waitForExistence(timeout: 5), "newest archived bookmark missing")
        shot("02-archives")
        search.tap()
        search.typeText("Archivé")
        XCTAssertTrue(row("Archivé un").waitForExistence(timeout: 5), "search inside the archived filter failed")
        XCTAssertTrue(row("Archivé deux").exists)
        closeSearch(search)
        button(prefix: "Tous").tap()

        search.tap()
        search.typeText("notes Markdown")
        XCTAssertTrue(row("Avec des notes Markdown").waitForExistence(timeout: 5))
        row("Avec des notes Markdown").tap()
        XCTAssertTrue(app.buttons["Ouvrir"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(text("Points clés").exists, "heading missing")
        XCTAssertTrue(text("Gras").exists, "bold line missing")
        XCTAssertTrue(text("Liste numérotée").exists, "numbered list missing")
        shot("02-detail-notes")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        closeSearch(search)
        search.tap()
        search.typeText("query")
        XCTAssertTrue(row("URL avec query").waitForExistence(timeout: 5))
        row("URL avec query").tap()
        XCTAssertTrue(app.buttons["Ouvrir"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(text("q=a+b").exists, "raw URL missing in detail")
        XCTAssertTrue(app.staticTexts["Oui"].exists, "shared flag should read Oui")
        shot("02-detail-query")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        closeSearch(search)

        app.tabBars.firstMatch.buttons["Tags"].tap()
        XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 5))
        shot("02-tags")
        print("TAG ROWS:", app.buttons.allElementsBoundByIndex.map(\.label).filter { $0.contains(",") })

        app.tabBars.firstMatch.buttons["Réglages"].tap()
        XCTAssertTrue(app.navigationBars["Réglages"].waitForExistence(timeout: 5))
        XCTAssertTrue(text("127.0.0.1").exists, "host missing in settings")
        XCTAssertTrue(text("linkding · 120 favoris").exists, "settings count: \(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'favoris'")).firstMatch.label)")
        XCTAssertTrue(app.buttons["Changer de serveur"].exists)
        shot("02-reglages")
    }

    func test03_MutationsReachTheServer() {
        XCTAssertTrue(connectedMarker.waitForExistence(timeout: 30), "not connected")
        let marker = "added-by-uitest-\(Int(Date().timeIntervalSince1970))"
        let url = "https://example.com/\(marker)"

        // Add.
        app.buttons["Ajouter un favori"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Nouveau favori"].waitForExistence(timeout: 5))
        let urlField = app.textFields["URL"].firstMatch
        urlField.tap()
        urlField.typeText(url)
        sleep(4) // real /check/: the server fetches the page
        print("SCRAPED TITLE:", app.textFields["Titre"].firstMatch.value ?? "nil")
        let tagInput = tagField("Ajouter un tag")
        tagInput.tap()
        tagInput.typeText("uitest\n")
        XCTAssertTrue(app.buttons["Retirer le tag uitest"].firstMatch.waitForExistence(timeout: 3))
        shot("03-ajout")
        app.buttons["Enregistrer"].firstMatch.tap()
        XCTAssertTrue(row("Example Domain").waitForExistence(timeout: 10), "new bookmark not listed")
        var found = serverBookmarks(matching: marker)
        XCTAssertEqual(found.count, 1, "server should hold the new bookmark")
        XCTAssertEqual(found.first?["tag_names"] as? [String], ["uitest"])
        XCTAssertEqual(found.first?["unread"] as? Bool, true, "unread by default not sent")
        shot("03-liste")

        // Edit the title.
        row("Example Domain").tap()
        XCTAssertTrue(app.buttons["Modifier"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Modifier"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Modifier"].waitForExistence(timeout: 5))
        clearAndType(app.textFields["Titre"].firstMatch, "Ajouté par UI test")
        app.buttons["Enregistrer"].firstMatch.tap()
        XCTAssertTrue(text("Ajouté par UI test").waitForExistence(timeout: 10), "edited title not shown")
        found = serverBookmarks(matching: marker)
        XCTAssertEqual(found.first?["title"] as? String, "Ajouté par UI test", "title not saved on the server")

        // Unread toggle from the detail.
        app.switches["Non lu"].firstMatch.tap()
        sleep(2)
        found = serverBookmarks(matching: marker)
        XCTAssertEqual(found.first?["unread"] as? Bool, false, "unread toggle not sent")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Archive by swipe, check the archived endpoint, unarchive.
        XCTAssertTrue(row("Ajouté par UI test").waitForExistence(timeout: 5))
        row("Ajouté par UI test").swipeLeft()
        XCTAssertTrue(app.buttons["Archiver"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Archiver"].firstMatch.tap()
        expectGone(row("Ajouté par UI test"), "archived row still listed")
        sleep(2)
        XCTAssertEqual(serverBookmarks(matching: marker, archived: true).count, 1, "server did not archive")
        button(prefix: "Archivés").tap()
        XCTAssertTrue(row("Ajouté par UI test").waitForExistence(timeout: 5))
        row("Ajouté par UI test").swipeLeft()
        XCTAssertTrue(app.buttons["Désarchiver"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Désarchiver"].firstMatch.tap()
        expectGone(row("Ajouté par UI test"), "unarchived row still in Archivés")
        sleep(2)
        XCTAssertEqual(serverBookmarks(matching: marker).count, 1, "server did not unarchive")
        button(prefix: "Tous").tap()

        // Duplicate detection against the real /check/.
        app.buttons["Ajouter un favori"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Nouveau favori"].waitForExistence(timeout: 5))
        let url2 = app.textFields["URL"].firstMatch
        url2.tap()
        url2.typeText("https://shared.example/")
        XCTAssertTrue(text("Déjà enregistré").waitForExistence(timeout: 10), "real duplicate not detected")
        XCTAssertEqual(app.textFields["Titre"].firstMatch.value as? String, "Partagé sur l’instance")
        shot("03-doublon-reel")
        app.buttons["Annuler"].firstMatch.tap()

        // Delete from the context menu.
        XCTAssertTrue(row("Ajouté par UI test").waitForExistence(timeout: 5))
        row("Ajouté par UI test").press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Supprimer"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Supprimer"].firstMatch.tap()
        expectGone(row("Ajouté par UI test"), "deleted row still listed")
        sleep(2)
        XCTAssertEqual(serverBookmarks(matching: marker).count, 0, "server did not delete")
    }

    func test04_ShareExtensionFromSafari() {
        XCTAssertTrue(connectedMarker.waitForExistence(timeout: 30), "not connected")
        let marker = "shared-from-safari-\(Int(Date().timeIntervalSince1970))"
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        safari.open(URL(string: "https://example.com/\(marker)")!)
        sleep(4)
        dump("04-hierarchy-safari", of: safari)
        var share = safari.buttons.matching(NSPredicate(format: "identifier == 'ShareButton' OR label == 'Partager'")).firstMatch
        if !share.waitForExistence(timeout: 5) {
            // Safari on iOS 27 keeps Share inside the page menu.
            let menu = safari.buttons["MoreMenuButton"].firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 5), "Safari page menu missing")
            menu.tap()
            share = safari.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Partager'")).firstMatch
            XCTAssertTrue(share.waitForExistence(timeout: 5), "Share entry missing in the page menu")
        }
        share.tap()
        sleep(2)
        dump("04-hierarchy-sharesheet", of: safari)
        shot("04-share-sheet", of: safari)
        var dingmark = safari.descendants(matching: .any).matching(NSPredicate(format: "label == 'Dingmark'")).firstMatch
        if !dingmark.waitForExistence(timeout: 5) {
            // First run: the app sits behind "Plus".
            let more = safari.descendants(matching: .any).matching(NSPredicate(format: "label == 'Plus' OR label == 'More'")).firstMatch
            if more.exists {
                more.tap()
                sleep(1)
                dump("04-hierarchy-more", of: safari)
                dingmark = safari.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Dingmark'")).firstMatch
            }
        }
        XCTAssertTrue(dingmark.waitForExistence(timeout: 5), "Dingmark not offered in the share sheet")
        dingmark.tap()
        sleep(3)
        dump("04-hierarchy-extension", of: safari)
        shot("04-extension", of: safari)
        let save = safari.buttons["Enregistrer"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "extension form missing")
        XCTAssertTrue(safari.staticTexts["Dingmark"].exists)
        XCTAssertFalse(safari.staticTexts["Dingmark n’est pas connecté"].exists, "extension does not see the session")
        print("EXTENSION TITLE FIELD:", safari.textFields["Titre"].firstMatch.value ?? "nil")
        let extensionTagField = safari.textFields.matching(NSPredicate(format: "label == 'Ajouter un tag' OR placeholderValue == 'Ajouter un tag'")).firstMatch
        if extensionTagField.waitForExistence(timeout: 3) {
            extensionTagField.tap()
            extensionTagField.typeText("safari\n")
        }
        shot("04-extension-remplie", of: safari)
        let full = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        full.name = "04-plein-ecran-avant-save"
        full.lifetime = .keepAlways
        add(full)
        print("SAVE BUTTON:", save.debugDescription.prefix(300))
        print("SAVE ENABLED:", save.isEnabled, "HITTABLE:", save.isHittable, "FRAME:", save.frame)
        save.tap()
        sleep(1)
        let full2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        full2.name = "04-plein-ecran-1s-apres-save"
        full2.lifetime = .keepAlways
        add(full2)
        sleep(3)
        var found = serverBookmarks(matching: marker)
        if found.isEmpty, safari.buttons["Enregistrer"].firstMatch.exists {
            print("SAVE TAP HAD NO EFFECT, retrying with a coordinate tap")
            safari.buttons["Enregistrer"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            sleep(4)
            found = serverBookmarks(matching: marker)
        }
        if found.isEmpty, safari.buttons["Enregistrer"].firstMatch.exists {
            print("COORDINATE TAP HAD NO EFFECT, testing whether Annuler responds")
            safari.buttons["Annuler"].firstMatch.tap()
            sleep(2)
            print("ANNULER RESPONDED:", !safari.buttons["Enregistrer"].firstMatch.exists)
            shot("04-apres-annuler", of: safari)
        }
        XCTAssertEqual(found.count, 1, "share extension did not save on the server")
        XCTAssertEqual(found.first?["tag_names"] as? [String], ["safari"])
        shot("04-apres-enregistrement", of: safari)
        guard !found.isEmpty else { return }

        // Back in the foreground the app refreshes and lists the shared bookmark (scraped title, tag safari).
        app.activate()
        let sharedRow = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Example Domain' AND label CONTAINS 'safari'")).firstMatch
        XCTAssertTrue(sharedRow.waitForExistence(timeout: 15), "bookmark shared from Safari not in the list after coming back")
        shot("04-app-apres-partage")
        if let id = found.first?["id"] as? Int {
            _ = api("DELETE", "/api/bookmarks/\(id)/")
        }
    }

    func test05_SignOut() {
        XCTAssertTrue(connectedMarker.waitForExistence(timeout: 30), "not connected")
        app.tabBars.firstMatch.buttons["Réglages"].tap()
        app.buttons["Changer de serveur"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Se déconnecter"].firstMatch.waitForExistence(timeout: 5), "confirmation dialog missing")
        shot("05-confirmation")
        app.buttons["Se déconnecter"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Tester la connexion"].firstMatch.waitForExistence(timeout: 10), "login screen missing after sign out")
        let serverValue = app.textFields["links.example.org"].firstMatch.value as? String
        XCTAssertTrue(serverValue == "" || serverValue == "links.example.org", "server field should be empty after sign out, got \(serverValue ?? "nil")")
        shot("05-deconnecte")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Tester la connexion"].firstMatch.waitForExistence(timeout: 10), "token survived the sign out")
    }
}
