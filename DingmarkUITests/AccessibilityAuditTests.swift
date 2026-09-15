import XCTest

/// Xcode's accessibility audit on every screen of the demo app. Missing
/// descriptions, wrong traits and small hit regions fail the test. Contrast,
/// Dynamic Type and clipped text are printed only: the accent colour is a
/// design decision, toolbar items and search prompts belong to the system,
/// and row descriptions are truncated to two lines on purpose.
final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(row("Tailscale SSH").waitForExistence(timeout: 15), "list did not load")
    }

    private func row(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private static let reportedOnly: XCUIAccessibilityAuditType = [.contrast, .dynamicType, .textClipped]

    private func audit(_ screen: String) throws {
        try app.performAccessibilityAudit(for: .all) { issue in
            let element = issue.element.map { "\($0.elementType.rawValue) \"\($0.label)\"" } ?? "?"
            let ignored = Self.reportedOnly.contains(issue.auditType)
            print("A11Y [\(screen)] \(ignored ? "reported" : "FAIL") \(issue.compactDescription) — \(element)")
            return ignored
        }
    }

    func test01_Library() throws {
        try audit("liste")
    }

    func test02_Detail() throws {
        row("Tailscale SSH").tap()
        XCTAssertTrue(app.buttons["Ouvrir"].firstMatch.waitForExistence(timeout: 5))
        try audit("détail")
    }

    func test03_ReadingQueue() throws {
        app.tabBars.buttons["À lire"].tap()
        XCTAssertTrue(app.navigationBars["À lire"].waitForExistence(timeout: 5))
        try audit("à lire")
    }

    func test04_TagsAndSettings() throws {
        app.tabBars.buttons["Tags"].tap()
        XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 5))
        try audit("tags")
        app.tabBars.buttons["Réglages"].tap()
        XCTAssertTrue(app.navigationBars["Réglages"].waitForExistence(timeout: 5))
        try audit("réglages")
    }

    func test05_AddSheet() throws {
        app.buttons["Ajouter un favori"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Nouveau favori"].waitForExistence(timeout: 5))
        try audit("ajout")
        app.buttons["Annuler"].firstMatch.tap()
    }

    func test06_SelectionMode() throws {
        app.buttons["Sélectionner"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Tout"].firstMatch.waitForExistence(timeout: 5))
        row("Tailscale SSH").tap()
        try audit("sélection")
        app.buttons["OK"].firstMatch.tap()
    }
}
