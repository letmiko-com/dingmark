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
