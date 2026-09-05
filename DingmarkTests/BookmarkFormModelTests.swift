import Testing
import Foundation
@testable import Dingmark

@Suite("BookmarkFormModel")
@MainActor
struct BookmarkFormModelTests {
    private func makeModel(prefill: String? = nil) -> BookmarkFormModel {
        BookmarkFormModel(api: DemoLinkdingClient(latency: .zero), mode: .create, suggestionPool: [], prefillURL: prefill)
    }

    @Test("pasted text: the link is kept, the surrounding words dropped")
    func pastedText() {
        let model = makeModel()
        model.applyPasted("  Regarde ça : https://restic.net/docs ok ")
        #expect(model.url == "https://restic.net/docs")
        #expect(model.canSave)
    }

    @Test("pasted bare host is accepted and normalised with https")
    func pastedHost() {
        let model = makeModel()
        model.applyPasted("links.example.org/x")
        #expect(model.url == "links.example.org/x")
        #expect(model.normalizedURL == "https://links.example.org/x")
    }

    @Test("URL without a dotted host cannot be saved")
    func invalidURL() {
        let model = makeModel(prefill: "nope")
        #expect(model.normalizedURL == nil)
        #expect(!model.canSave)
    }
}

@Suite("BookmarkFormModel check results")
@MainActor
struct BookmarkFormModelCheckTests {
    private func makeModel(unreadByDefault: Bool = true) -> BookmarkFormModel {
        BookmarkFormModel(api: DemoLinkdingClient(latency: .zero), mode: .create, suggestionPool: [], defaultTags: ["inbox"], unreadByDefault: unreadByDefault)
    }

    private func existing() -> CheckResponse {
        CheckResponse(bookmark: Bookmark(id: 5, url: "https://restic.net", title: "Restic", description: "Backups", notes: "n", unread: false, shared: true, tagNames: ["selfhosting", "inbox"]),
                      metadata: nil, autoTags: nil)
    }

    private func scraped(_ title: String) -> CheckResponse {
        CheckResponse(bookmark: nil, metadata: .init(title: title, description: "Scraped \(title)", previewImage: nil), autoTags: ["auto"])
    }

    @Test("a duplicate pre-fills the form, another URL drops the pre-filled values")
    func duplicateThenOtherURL() {
        let model = makeModel()
        model.applyCheck(existing())
        #expect(model.existing?.id == 5)
        #expect(model.title == "Restic" && model.description == "Backups" && model.notes == "n")
        #expect(model.tags == ["inbox", "selfhosting"])
        #expect(model.unread == false && model.shared == true)

        model.applyCheck(scraped("Other page"))
        #expect(model.existing == nil)
        #expect(model.title == "Other page")
        #expect(model.description == "Scraped Other page")
        #expect(model.notes == "")
        #expect(model.tags == ["inbox"], "tags added by the duplicate must go, the default tag stays")
        #expect(model.unread == true && model.shared == false, "flags return to the defaults")
        #expect(model.autoTags == ["auto"])
    }

    @Test("values typed by the user survive a new check")
    func userEditsKept() {
        let model = makeModel()
        model.applyCheck(scraped("First"))
        model.title = "Mon titre"
        model.tags.append("perso")
        model.applyCheck(scraped("Second"))
        #expect(model.title == "Mon titre")
        #expect(model.description == "Scraped Second", "untouched description follows the URL")
        #expect(model.tags == ["inbox", "perso"])
    }
}

@Suite("DemoLinkdingClient")
struct DemoLinkdingClientTests {
    @Test("only the exact URL is a duplicate")
    func duplicateIsExact() async throws {
        let client = DemoLinkdingClient(latency: .zero)
        #expect(try await client.check(url: "https://restic.net").bookmark?.id == 5)
        #expect(try await client.check(url: "https://restic.net/docs").bookmark == nil)
    }
}
