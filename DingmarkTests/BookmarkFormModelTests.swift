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

@Suite("BookmarkFormModel save safety", .timeLimit(.minutes(1)))
@MainActor
struct BookmarkFormSaveTests {
    private let original = Bookmark(id: 42, url: "https://example.org/a", title: "A", notes: "Keep these notes",
                                    isArchived: true, unread: false, shared: true, tagNames: ["keep"])

    @Test("changing URL clears the old duplicate before the next response")
    func changedURL() async throws {
        let api = ControlledFormAPI()
        var events = api.events.makeAsyncIterator()
        let form = BookmarkFormModel(api: api, mode: .create, suggestionPool: [], prefillURL: original.url, checkDelay: .zero)
        form.applyCheck(CheckResponse(bookmark: original))
        form.url = "https://example.org/b"
        #expect(form.existing == nil)
        #expect(form.notes.isEmpty && form.title.isEmpty && form.tags.isEmpty)
        let save = Task { try await form.save() }
        let check = try #require(await events.next())
        #expect(check.kind == .check(form.url))
        await api.succeed(check, with: .check(CheckResponse()))
        let create = try #require(await events.next())
        guard case .create(let draft) = create.kind else { Issue.record("Expected a create for B, never a PATCH of A"); return }
        #expect(draft.url == form.url && draft.notes.isEmpty)
        await api.succeed(create, with: .bookmark(Bookmark(id: 43, url: draft.url)))
        #expect(try await save.value.id == 43)
    }

    @Test("an immediate save checks first and preserves an archived duplicate")
    func immediateSave() async throws {
        let api = ControlledFormAPI()
        var events = api.events.makeAsyncIterator()
        let form = BookmarkFormModel(api: api, mode: .create, suggestionPool: [], prefillURL: original.url)
        let save = Task { try await form.save() }
        let check = try #require(await events.next())
        #expect(check.kind == .check(original.url))
        #expect(await api.requestCount == 1)
        await api.succeed(check, with: .check(CheckResponse(bookmark: original)))
        let update = try #require(await events.next())
        #expect(update.kind == .patch(original.id, BookmarkPatch()))
        await api.succeed(update, with: .bookmark(original))
        let saved = try await save.value
        #expect(saved.notes == original.notes && saved.tagNames == original.tagNames && saved.isArchived)
    }

    @Test("a failed duplicate check aborts the save and can be retried")
    func failedCheck() async throws {
        let api = ControlledFormAPI()
        var events = api.events.makeAsyncIterator()
        let form = BookmarkFormModel(api: api, mode: .create, suggestionPool: [], prefillURL: original.url)
        let save = Task { try await form.save() }
        await api.fail(try #require(await events.next()))
        await #expect(throws: LinkdingError.http(status: 500)) { try await save.value }
        #expect(await api.requestCount == 1)
        #expect(form.canSave && form.saveError == .http(status: 500))
        let retry = Task { try await form.save() }
        let check = try #require(await events.next())
        #expect(check.kind == .check(original.url))
        await api.succeed(check, with: .check(CheckResponse(bookmark: original)))
        let update = try #require(await events.next())
        await api.succeed(update, with: .bookmark(original))
        _ = try await retry.value
        #expect(form.saveError == nil)
    }

    @Test("late responses for a replaced URL cannot restore the old duplicate")
    func lateCheck() async throws {
        let api = ControlledFormAPI()
        var events = api.events.makeAsyncIterator()
        let form = BookmarkFormModel(api: api, mode: .create, suggestionPool: [], checkDelay: .zero)
        form.url = original.url
        let old = try #require(await events.next())
        form.url = "https://example.org/b"
        let current = try #require(await events.next())
        let save = Task { try await form.save() }
        await api.succeed(old, with: .check(CheckResponse(bookmark: original)))
        await api.succeed(current, with: .check(CheckResponse()))
        let create = try #require(await events.next())
        guard case .create(let draft) = create.kind else { Issue.record("Stale check caused a PATCH"); return }
        #expect(draft.url == form.url && draft.notes.isEmpty)
        await api.succeed(create, with: .bookmark(Bookmark(id: 43, url: draft.url)))
        _ = try await save.value
        #expect(form.existing == nil)
    }

    @Test("URL changes during a save invalidate the waiting save")
    func changeDuringSave() async throws {
        let api = ControlledFormAPI()
        var events = api.events.makeAsyncIterator()
        let form = BookmarkFormModel(api: api, mode: .create, suggestionPool: [], prefillURL: original.url, checkDelay: .zero)
        let save = Task { try await form.save() }
        let check = try #require(await events.next())
        form.url = "invalid"
        await api.succeed(check, with: .check(CheckResponse(bookmark: original)))
        await #expect(throws: CancellationError.self) { try await save.value }
        #expect(await api.requestCount == 1)
        #expect(form.existing == nil)
    }

    @Test("editing a title preserves fields another client changed after opening the form")
    func minimalPatch() async throws {
        let api = DemoLinkdingClient(bookmarks: [original], tags: [], latency: .zero)
        let form = BookmarkFormModel(api: api, mode: .edit(original), suggestionPool: [])
        form.title = "Edited"
        _ = try await api.update(id: original.id, BookmarkPatch(notes: "New external notes", unread: true, tagNames: ["external"]))
        let saved = try await form.save()
        #expect(saved.title == "Edited")
        #expect(saved.notes == "New external notes" && saved.unread && saved.tagNames == ["external"])
    }

    @Test("clearing fields explicitly in edit mode still sends empty values")
    func explicitClear() async throws {
        let api = DemoLinkdingClient(bookmarks: [original], tags: [], latency: .zero)
        let form = BookmarkFormModel(api: api, mode: .edit(original), suggestionPool: [])
        form.notes = ""
        form.tags = []
        let saved = try await form.save()
        #expect(saved.notes.isEmpty && saved.tagNames.isEmpty)
        #expect(saved.title == original.title && saved.isArchived)
    }

    @Test("a concurrent duplicate POST omits fields that would erase existing data")
    func conservativeCreatePayload() throws {
        let draft = BookmarkDraft(url: original.url, title: "Title", unread: true)
        let data = try LinkdingJSON.makeEncoder().encode(draft)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["notes"] == nil && json["tag_names"] == nil)
        #expect(json["is_archived"] == nil && json["shared"] == nil)
        #expect(json["unread"] as? Bool == true)
    }
}

private actor ControlledFormAPI: LinkdingAPI {
    enum Kind: Hashable, Sendable {
        case check(String)
        case create(BookmarkDraft)
        case patch(Int, BookmarkPatch)
    }
    struct Request: Sendable {
        let id = UUID()
        let kind: Kind
    }
    enum Response: Sendable {
        case check(CheckResponse)
        case bookmark(Bookmark)
    }
    nonisolated let events: AsyncStream<Request>
    private let continuation: AsyncStream<Request>.Continuation
    private var pending: [UUID: CheckedContinuation<Response, Error>] = [:]
    private(set) var requestCount = 0
    init() { (events, continuation) = AsyncStream.makeStream() }
    private func request(_ kind: Kind) async throws -> Response {
        let request = Request(kind: kind)
        requestCount += 1
        return try await withCheckedThrowingContinuation { promise in
            pending[request.id] = promise
            continuation.yield(request)
        }
    }
    func succeed(_ request: Request, with response: Response) { pending.removeValue(forKey: request.id)?.resume(returning: response) }
    func fail(_ request: Request) { pending.removeValue(forKey: request.id)?.resume(throwing: LinkdingError.http(status: 500)) }
    func check(url: String) async throws -> CheckResponse {
        guard case .check(let response) = try await request(.check(url)) else { throw LinkdingError.decoding }
        return response
    }
    func create(_ draft: BookmarkDraft) async throws -> Bookmark {
        guard case .bookmark(let result) = try await request(.create(draft)) else { throw LinkdingError.decoding }
        return result
    }
    func update(id: Int, _ patch: BookmarkPatch) async throws -> Bookmark {
        guard case .bookmark(let result) = try await request(.patch(id, patch)) else { throw LinkdingError.decoding }
        return result
    }
    func testConnection() async throws -> Int { 0 }
    func fetchAllBookmarks() async throws -> [Bookmark] { [] }
    func fetchTags() async throws -> [String] { [] }
    func setArchived(id: Int, _ archived: Bool) async throws {}
    func delete(id: Int) async throws {}
}
