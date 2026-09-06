import Foundation
import Testing
@testable import Dingmark

@Suite("BookmarkStore concurrency", .timeLimit(.minutes(1)))
@MainActor
struct BookmarkStoreTests {
    private let first = Bookmark(id: 1, url: "https://one.example", title: "One",
                                 dateAdded: Date(timeIntervalSince1970: 100), dateModified: Date(timeIntervalSince1970: 100))
    private let second = Bookmark(id: 2, url: "https://two.example", title: "Two",
                                  dateAdded: Date(timeIntervalSince1970: 200), dateModified: Date(timeIntervalSince1970: 200))

    private func makeStore(_ api: ControlledStoreAPI, bookmarks: [Bookmark]) -> (BookmarkStore, BookmarkCache) {
        let cache = BookmarkCache(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("store-test-\(UUID()).json"))
        cache.save(CacheSnapshot(bookmarks: bookmarks, tags: [], syncedAt: Date(timeIntervalSince1970: 100), serverHost: nil))
        let store = BookmarkStore(api: api, cache: cache)
        store.loadFromCache()
        return (store, cache)
    }

    @Test("rapid toggles use current state and reach the server in order")
    func rapidToggles() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let one = try #require(store.toggleUnread(first))
        let request = try #require(await events.next())
        // A row may still hold the original value on the next tap.
        let two = try #require(store.toggleUnread(first))
        #expect(store.bookmark(id: 1)?.unread == false)
        #expect(request.kind == .patch(1, BookmarkPatch(unread: true)))
        #expect(await api.requestCount == 1)
        var saved = first
        saved.unread = true
        await api.succeed(request, with: .bookmark(saved))
        _ = try await one.value
        #expect(store.bookmark(id: 1)?.unread == false)
        let next = try #require(await events.next())
        #expect(next.kind == .patch(1, BookmarkPatch(unread: false)))
        await api.succeed(next, with: .bookmark(first))
        _ = try await two.value
        #expect(store.bookmarks == [first])
        #expect(cache.load()?.bookmarks == [first])
    }

    @Test("two failed toggles restore the confirmed value and timestamp")
    func failedToggles() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let one = try #require(store.toggleUnread(first))
        let request = try #require(await events.next())
        let two = try #require(store.toggleUnread(first))
        await api.fail(request)
        _ = await one.result
        #expect(store.bookmark(id: 1)?.unread == false)
        await api.fail(try #require(await events.next()))
        _ = await two.result
        #expect(store.bookmarks == [first])
        #expect(cache.load()?.bookmarks == [first])
    }

    @Test("failed unarchive restores the preceding successful archive")
    func archiveRollback() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let one = try #require(store.setArchived(first, true))
        let request = try #require(await events.next())
        let two = try #require(store.setArchived(first, false))
        #expect(store.bookmark(id: 1)?.isArchived == false)
        await api.succeed(request)
        _ = try await one.value
        #expect(store.bookmark(id: 1)?.isArchived == false)
        let next = try #require(await events.next())
        #expect(next.kind == .archive(1, false))
        await api.fail(next)
        _ = await two.result
        #expect(store.bookmark(id: 1)?.isArchived == true)
        #expect(cache.load()?.bookmarks.first?.isArchived == true)
    }

    @Test("an unread response preserves a later optimistic archive")
    func overlappingFields() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let one = try #require(store.toggleUnread(first))
        let request = try #require(await events.next())
        let two = try #require(store.setArchived(first, true))
        var saved = first
        saved.unread = true
        await api.succeed(request, with: .bookmark(saved))
        _ = try await one.value
        #expect(store.bookmark(id: 1)?.isArchived == true)
        #expect(store.bookmark(id: 1)?.unread == true)
        await api.succeed(try #require(await events.next()))
        _ = try await two.value
        #expect(cache.load()?.bookmarks.first?.isArchived == true)
    }

    @Test("different bookmarks can be written independently")
    func independentBookmarks() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first, second])
        defer { cache.clear() }
        let one = try #require(store.delete(first))
        let two = try #require(store.delete(second))
        let requests = [try #require(await events.next()), try #require(await events.next())]
        #expect(Set(requests.map(\.kind)) == [.delete(1), .delete(2)])
        for request in requests.reversed() { await api.succeed(request) }
        _ = try await one.value
        _ = try await two.value
        #expect(store.bookmarks.isEmpty)
    }

    @Test("failed deletion restores order and leaves the offline cache confirmed")
    func deletionCache() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first, second])
        defer { cache.clear() }
        let deletion = try #require(store.delete(first))
        #expect(store.bookmarks == [second])
        #expect(cache.load()?.bookmarks.map(\.id) == [1, 2])
        await api.fail(try #require(await events.next()))
        _ = await deletion.result
        #expect(store.bookmarks == [first, second])
        #expect(cache.load()?.bookmarks.map(\.id) == [1, 2])
    }

    @Test("a refresh overlapping a completed deletion cannot resurrect it")
    func staleRefresh() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let refresh = Task { await store.refresh() }
        let snapshot = try #require(await events.next())
        let deletion = try #require(store.delete(first))
        await api.succeed(try #require(await events.next()))
        _ = try await deletion.value
        await api.succeed(snapshot, with: .bookmarks([first]))
        let retry = try #require(await events.next())
        #expect(retry.kind == .fetch)
        #expect(store.bookmarks.isEmpty)
        await api.succeed(retry, with: .bookmarks([]))
        await refresh.value
        #expect(store.bookmarks.isEmpty)
        #expect(cache.load()?.bookmarks.isEmpty == true)
    }

    @Test("a refresh waits for an in-flight write before fetching")
    func refreshWaitsForWrites() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let deletion = try #require(store.delete(first))
        let request = try #require(await events.next())
        let refresh = Task { await store.refresh() }
        await api.succeed(request)
        _ = try await deletion.value
        let snapshot = try #require(await events.next())
        #expect(snapshot.kind == .fetch)
        await api.succeed(snapshot, with: .bookmarks([]))
        await refresh.value
        #expect(store.bookmarks.isEmpty)
    }

    @Test("old refresh completion cannot repopulate a new session or clear its spinner", arguments: [false, true])
    func sessionRefresh(fails: Bool) async throws {
        let oldAPI = ControlledStoreAPI()
        let newAPI = ControlledStoreAPI()
        var oldEvents = oldAPI.events.makeAsyncIterator()
        var newEvents = newAPI.events.makeAsyncIterator()
        let (store, cache) = makeStore(oldAPI, bookmarks: [first])
        defer { cache.clear() }
        let oldRefresh = Task { await store.refresh() }
        let oldRequest = try #require(await oldEvents.next())
        store.reset()
        store.configure(api: newAPI)
        let newRefresh = Task { await store.refresh() }
        let newRequest = try #require(await newEvents.next())
        if fails { await oldAPI.fail(oldRequest) }
        else { await oldAPI.succeed(oldRequest, with: .bookmarks([first])) }
        await oldRefresh.value
        #expect(store.bookmarks.isEmpty)
        #expect(store.isLoading)
        #expect(!store.isOffline)
        #expect(store.loadError == nil)
        #expect(cache.load() == nil)
        await newAPI.succeed(newRequest, with: .bookmarks([second]))
        await newRefresh.value
        #expect(store.bookmarks == [second])
        #expect(!store.isLoading)
    }

    @Test("reset ignores late write results and cancels queued writes", arguments: [false, true])
    func sessionWrites(fails: Bool) async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let one = try #require(store.toggleUnread(first))
        let request = try #require(await events.next())
        let two = try #require(store.delete(first))
        store.reset()
        if fails { await api.fail(request) }
        else { await api.succeed(request, with: .bookmark(first)) }
        _ = await one.result
        _ = await two.result
        #expect(await api.requestCount == 1)
        #expect(store.bookmarks.isEmpty)
        #expect(store.toast == nil)
        #expect(cache.load() == nil)
        #expect(store.toggleUnread(first) == nil)
    }

    @Test("cancelling a refresh ignores even a successful non-cooperative response")
    func cancelledRefresh() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let refresh = Task { await store.refresh() }
        let request = try #require(await events.next())
        refresh.cancel()
        await api.succeed(request, with: .bookmarks([second]))
        await refresh.value
        #expect(store.bookmarks == [first])
        #expect(!store.isLoading)
        #expect(!store.isOffline)
        #expect(store.loadError == nil)
    }

    @Test("form edits share the queue and preserve later list actions")
    func formEdits() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let formAPI = try #require(store.makeFormAPI())
        let form = BookmarkFormModel(api: formAPI, mode: .edit(first), suggestionPool: [])
        form.title = "Edited"
        form.tags = ["new"]
        let save = Task { try await form.save() }
        let request = try #require(await events.next())
        #expect(store.bookmark(id: 1)?.title == "Edited")
        let toggle = try #require(store.toggleUnread(first))
        var saved = first
        saved.title = "Edited"
        saved.tagNames = ["new"]
        await api.succeed(request, with: .bookmark(saved))
        _ = try await save.value
        #expect(store.bookmark(id: 1)?.unread == true)
        #expect(store.bookmark(id: 1)?.title == "Edited")
        #expect(store.knownTags == ["new"])
        #expect(store.successCount == 1)
        let next = try #require(await events.next())
        saved.unread = true
        await api.succeed(next, with: .bookmark(saved))
        _ = try await toggle.value
        #expect(store.bookmarks == [saved])
    }

    @Test("a form failure restores the bookmark and remains an inline error")
    func formFailure() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let form = BookmarkFormModel(api: try #require(store.makeFormAPI()), mode: .edit(first), suggestionPool: [])
        form.title = "Edited"
        let save = Task { try await form.save() }
        await api.fail(try #require(await events.next()))
        _ = await save.result
        #expect(store.bookmarks == [first])
        #expect(form.saveError == .http(status: 500))
        #expect(store.toast == nil)
    }

    @Test("an old form cannot save into another session", arguments: [false, true])
    func oldForm(started: Bool) async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let formAPI = try #require(store.makeFormAPI())
        let draft = BookmarkDraft(url: second.url, title: second.title)
        if started {
            let save = Task { try await formAPI.create(draft) }
            let request = try #require(await events.next())
            store.reset()
            store.configure(api: ControlledStoreAPI())
            await api.succeed(request, with: .bookmark(second))
            _ = await save.result
        } else {
            store.reset()
            store.configure(api: ControlledStoreAPI())
            await #expect(throws: CancellationError.self) { try await formAPI.create(draft) }
            #expect(await api.requestCount == 0)
        }
        #expect(store.bookmarks.isEmpty)
        #expect(store.toast == nil)
        #expect(store.successCount == 0)
        #expect(cache.load() == nil)
    }

    @Test("a create returning an existing ID cannot race with a later deletion")
    func duplicateCreate() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let formAPI = try #require(store.makeFormAPI())
        let create = Task { try await formAPI.create(BookmarkDraft(url: first.url, title: "Duplicate")) }
        let request = try #require(await events.next())
        let deletion = try #require(store.delete(first))
        #expect(await api.requestCount == 1)
        await api.succeed(request, with: .bookmark(first))
        _ = try await create.value
        #expect(store.bookmarks.isEmpty)
        let next = try #require(await events.next())
        #expect(next.kind == .delete(1))
        await api.succeed(next)
        _ = try await deletion.value
        #expect(cache.load()?.bookmarks.isEmpty == true)
    }

    @Test("a refresh overlapping a create retries instead of losing the new bookmark")
    func refreshDuringCreate() async throws {
        let api = ControlledStoreAPI()
        var events = api.events.makeAsyncIterator()
        let (store, cache) = makeStore(api, bookmarks: [first])
        defer { cache.clear() }
        let refresh = Task { await store.refresh() }
        let snapshot = try #require(await events.next())
        let formAPI = try #require(store.makeFormAPI())
        let create = Task { try await formAPI.create(BookmarkDraft(url: second.url)) }
        await api.succeed(try #require(await events.next()), with: .bookmark(second))
        _ = try await create.value
        await api.succeed(snapshot, with: .bookmarks([first]))
        let retry = try #require(await events.next())
        #expect(store.bookmarks.map(\.id) == [2, 1])
        await api.succeed(retry, with: .bookmarks([second, first]))
        await refresh.value
        #expect(store.bookmarks == [second, first])
    }
}

/// Requests finish only when the test releases them. Cancellation is
/// deliberately ignored to exercise late responses from an old session.
private actor ControlledStoreAPI: LinkdingAPI {
    enum Kind: Hashable, Sendable {
        case fetch
        case patch(Int, BookmarkPatch)
        case archive(Int, Bool)
        case delete(Int)
        case create
    }

    struct Request: Sendable {
        let id = UUID()
        let kind: Kind
    }

    enum Response: Sendable {
        case bookmarks([Bookmark])
        case bookmark(Bookmark)
        case empty
    }

    nonisolated let events: AsyncStream<Request>
    private let eventContinuation: AsyncStream<Request>.Continuation
    private var pending: [UUID: CheckedContinuation<Response, Error>] = [:]
    private(set) var requestCount = 0

    init() {
        (events, eventContinuation) = AsyncStream.makeStream()
    }

    private func request(_ kind: Kind) async throws -> Response {
        let request = Request(kind: kind)
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[request.id] = continuation
            eventContinuation.yield(request)
        }
    }

    func succeed(_ request: Request, with response: Response = .empty) {
        pending.removeValue(forKey: request.id)?.resume(returning: response)
    }

    func fail(_ request: Request) {
        pending.removeValue(forKey: request.id)?.resume(throwing: LinkdingError.http(status: 500))
    }

    func testConnection() async throws -> Int { 0 }
    func fetchTags() async throws -> [String] { [] }
    func check(url: String) async throws -> CheckResponse { CheckResponse() }

    func fetchAllBookmarks() async throws -> [Bookmark] {
        guard case .bookmarks(let bookmarks) = try await request(.fetch) else { throw LinkdingError.decoding }
        return bookmarks
    }

    func create(_ draft: BookmarkDraft) async throws -> Bookmark {
        guard case .bookmark(let bookmark) = try await request(.create) else { throw LinkdingError.decoding }
        return bookmark
    }

    func update(id: Int, _ patch: BookmarkPatch) async throws -> Bookmark {
        guard case .bookmark(let bookmark) = try await request(.patch(id, patch)) else { throw LinkdingError.decoding }
        return bookmark
    }

    func setArchived(id: Int, _ archived: Bool) async throws { _ = try await request(.archive(id, archived)) }
    func delete(id: Int) async throws { _ = try await request(.delete(id)) }
}
