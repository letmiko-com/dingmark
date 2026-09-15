import Foundation
import Observation
import WidgetKit

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    /// Optional follow-up offered in the banner ("Archiver" after reading).
    var actionTitle: String? = nil
    var action: (@MainActor () -> Void)? = nil

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

/// Bookmarks in memory, cache on disk, server behind. Every mutation is
/// optimistic: local state first, request after, silent rollback on failure.
@MainActor @Observable
final class BookmarkStore {
    private(set) var bookmarks: [Bookmark] = []
    /// Tags known by the server, including those with no bookmark in cache.
    var knownTags: [String] = []
    var filter: QuickFilter = .all
    var tagFilter: String?
    var query = ""

    private(set) var isLoading = false
    private(set) var isOffline = false
    private(set) var lastSync: Date?
    private(set) var loadError: LinkdingError?
    private(set) var hasLoadedOnce = false
    var toast: Toast?
    /// Haptic triggers.
    private(set) var successCount = 0
    private(set) var destructiveCount = 0

    private var api: LinkdingAPI?
    private let cache: BookmarkCache
    private var cacheSessionID: UUID?
    private var refreshTask: Task<Void, Never>?
    private var refreshID: UUID?
    private var sessionID = UUID()
    private var revision = 0
    private var confirmed: [Bookmark] = []
    private var pending: [PendingWrite] = []
    private var writes: [UUID: Task<Bookmark?, Error>] = [:]

    private enum Write {
        case patch(Int, BookmarkPatch)
        case archive(Int, Bool)
        case delete(Int)
        case create(BookmarkDraft)

        var bookmarkID: Int? {
            switch self {
            case .patch(let id, _), .archive(let id, _), .delete(let id): return id
            case .create: return nil
            }
        }

        func apply(to list: inout [Bookmark], at date: Date) {
            guard let index = list.firstIndex(where: { $0.id == bookmarkID }) else { return }
            switch self {
            case .patch(_, let patch):
                if let value = patch.url { list[index].url = value }
                if let value = patch.title { list[index].title = value }
                if let value = patch.description { list[index].description = value }
                if let value = patch.notes { list[index].notes = value }
                if let value = patch.unread { list[index].unread = value }
                if let value = patch.shared { list[index].shared = value }
                if let value = patch.isArchived { list[index].isArchived = value }
                if let value = patch.tagNames { list[index].tagNames = value }
            case .archive(_, let archived): list[index].isArchived = archived
            case .delete:
                list.remove(at: index)
                return
            case .create: return
            }
            list[index].dateModified = date
        }

        func send(to api: LinkdingAPI) async throws -> Bookmark? {
            switch self {
            case .patch(let id, let patch): return try await api.update(id: id, patch)
            case .archive(let id, let archived): try await api.setArchived(id: id, archived)
            case .delete(let id): try await api.delete(id: id)
            case .create(let draft): return try await api.create(draft)
            }
            return nil
        }
    }

    private struct PendingWrite {
        let id = UUID()
        let operation: Write
        let date = Date.now
    }

    init(api: LinkdingAPI?, cache: BookmarkCache = .shared, cacheSessionID: UUID? = nil) {
        self.api = api
        self.cache = cache
        self.cacheSessionID = cacheSessionID
    }

    func configure(api: LinkdingAPI?, cacheSessionID: UUID? = nil) {
        invalidateRequests()
        self.api = api
        self.cacheSessionID = cacheSessionID
        publishBookmarks()
    }

    /// Forms use the same ordered writes as the list, bound to this session.
    func makeFormAPI() -> LinkdingAPI? {
        guard let api else { return nil }
        return FormAPI(store: self, api: api, sessionID: sessionID)
    }

    // MARK: Derived

    var counts: FilterCounts { BookmarkFilter.counts(bookmarks) }

    var filtered: [Bookmark] { BookmarkFilter.apply(bookmarks, filter: filter, tag: tagFilter, query: query) }

    /// Tags of the active bookmarks with their counts: what the Tags screen and
    /// the iPad sidebar list. A tag filter shows active bookmarks, so a tag
    /// carried only by archived ones would otherwise open an empty list.
    var tagCounts: [(name: String, count: Int)] { BookmarkFilter.tagCounts(bookmarks, includeArchived: false) }

    /// Usage across every bookmark, archived included: orders the suggestions.
    var tagUsage: [(name: String, count: Int)] { BookmarkFilter.tagCounts(bookmarks) }

    var allTagNames: [String] {
        var set = Set(knownTags)
        for b in bookmarks { set.formUnion(b.tagNames) }
        return set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var unreadBookmarks: [Bookmark] {
        bookmarks.filter { !$0.isArchived && $0.unread }.sorted { $0.dateAdded > $1.dateAdded }
    }

    func bookmark(id: Int) -> Bookmark? { bookmarks.first { $0.id == id } }

    var isEmptyServer: Bool { hasLoadedOnce && bookmarks.isEmpty && loadError == nil }

    // MARK: Loading

    func loadFromCache() {
        guard let snapshot = cache.load(sessionID: cacheSessionID) else { return }
        confirmed = snapshot.bookmarks
        publishBookmarks()
        knownTags = snapshot.tags
        lastSync = snapshot.syncedAt
        hasLoadedOnce = true
    }

    func refresh() async {
        guard let api, !isLoading else { return }
        loadFromCache()
        let id = UUID()
        let session = sessionID
        refreshID = id
        isLoading = true
        let task = Task { await self.performRefresh(api: api, session: session, id: id) }
        refreshTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func reset() {
        invalidateRequests()
        api = nil
        confirmed = []
        bookmarks = []
        knownTags = []
        lastSync = nil
        loadError = nil
        isOffline = false
        hasLoadedOnce = false
        filter = .all
        tagFilter = nil
        query = ""
        toast = nil
        cache.clear(sessionID: cacheSessionID)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Mutations

    @discardableResult
    func toggleUnread(_ bookmark: Bookmark) -> Task<Bookmark?, Error>? {
        guard let current = self.bookmark(id: bookmark.id), api != nil else { return nil }
        return enqueue(.patch(current.id, BookmarkPatch(unread: !current.unread)))
    }

    /// Explicit target value: safe when the caller's copy may be stale.
    @discardableResult
    func setUnread(_ bookmark: Bookmark, _ unread: Bool) -> Task<Bookmark?, Error>? {
        guard let current = self.bookmark(id: bookmark.id), api != nil, current.unread != unread else { return nil }
        return enqueue(.patch(current.id, BookmarkPatch(unread: unread)))
    }

    /// The user opened the page: an unread bookmark becomes read when the
    /// "mark read on open" preference is on (default).
    @discardableResult
    func recordOpen(_ bookmark: Bookmark, defaults: UserDefaults = AppGroup.defaults) -> Task<Bookmark?, Error>? {
        guard ReadingSettings.marksReadOnOpen(defaults) else { return nil }
        return setUnread(bookmark, false)
    }

    @discardableResult
    func setArchived(_ bookmark: Bookmark, _ archived: Bool) -> Task<Bookmark?, Error>? {
        guard self.bookmark(id: bookmark.id) != nil, api != nil else { return nil }
        destructiveCount += 1
        show(archived ? String(localized: "Archivé") : String(localized: "Désarchivé"))
        return enqueue(.archive(bookmark.id, archived))
    }

    @discardableResult
    func delete(_ bookmark: Bookmark) -> Task<Bookmark?, Error>? {
        guard self.bookmark(id: bookmark.id) != nil, api != nil else { return nil }
        destructiveCount += 1
        show(String(localized: "Supprimé"))
        return enqueue(.delete(bookmark.id))
    }

    // MARK: Bulk mutations

    /// One ordered write per bookmark (linkding has no bulk endpoint); a
    /// single banner and haptic for the whole selection.
    @discardableResult
    func markRead(ids: Set<Int>) -> [Task<Bookmark?, Error>] {
        let tasks = ids.compactMap { id in bookmark(id: id).flatMap { setUnread($0, false) } }
        if !tasks.isEmpty {
            successCount += 1
            show(String(localized: "\(tasks.count) marqués lus"))
        }
        return tasks
    }

    @discardableResult
    func setArchived(ids: Set<Int>, _ archived: Bool) -> [Task<Bookmark?, Error>] {
        guard api != nil else { return [] }
        let targets = ids.compactMap { bookmark(id: $0) }.filter { $0.isArchived != archived }
        guard !targets.isEmpty else { return [] }
        destructiveCount += 1
        show(archived ? String(localized: "\(targets.count) archivés") : String(localized: "\(targets.count) désarchivés"))
        return targets.map { enqueue(.archive($0.id, archived)) }
    }

    @discardableResult
    func delete(ids: Set<Int>) -> [Task<Bookmark?, Error>] {
        guard api != nil else { return [] }
        let targets = ids.compactMap { bookmark(id: $0) }
        guard !targets.isEmpty else { return [] }
        destructiveCount += 1
        show(String(localized: "\(targets.count) supprimés"))
        return targets.map { enqueue(.delete($0.id)) }
    }

    /// Adds tags to every selected bookmark, keeping the ones they have.
    /// Bookmarks that already carry all of them are left alone.
    @discardableResult
    func addTags(_ tags: [String], to ids: Set<Int>) -> [Task<Bookmark?, Error>] {
        guard api != nil else { return [] }
        let clean = TagList.parse(tags.joined(separator: ","))
        guard !clean.isEmpty else { return [] }
        var tasks: [Task<Bookmark?, Error>] = []
        for id in ids.sorted() {
            guard let current = bookmark(id: id) else { continue }
            let merged = TagList.parse((current.tagNames + clean).joined(separator: ","))
            guard merged != current.tagNames else { continue }
            tasks.append(enqueue(.patch(current.id, BookmarkPatch(tagNames: merged))))
        }
        if !tasks.isEmpty {
            successCount += 1
            show(String(localized: "Tags ajoutés à \(tasks.count) favoris"))
        }
        return tasks
    }

    func show(_ message: String) {
        toast = Toast(message: message)
    }

    func show(_ message: String, actionTitle: String, action: @escaping @MainActor () -> Void) {
        toast = Toast(message: message, actionTitle: actionTitle, action: action)
    }

    /// The page was closed from the reading queue. Marked read on open: offer
    /// to archive. Not marked (preference off): offer to mark read.
    func finishReading(_ bookmark: Bookmark, defaults: UserDefaults = AppGroup.defaults) {
        guard let current = self.bookmark(id: bookmark.id) else { return }
        if current.unread {
            show(String(localized: "Terminé ?"), actionTitle: String(localized: "Marquer lu")) { [weak self] in
                self?.setUnread(current, false)
            }
        } else if !current.isArchived {
            show(String(localized: "Lu"), actionTitle: String(localized: "Archiver")) { [weak self] in
                self?.setArchived(current, true)
            }
        }
    }

    // MARK: Private

    private func invalidateRequests() {
        sessionID = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        isLoading = false
        for task in writes.values { task.cancel() }
        writes.removeAll()
        pending.removeAll()
    }

    private func performRefresh(api: LinkdingAPI, session: UUID, id: UUID) async {
        defer {
            // An old session must not clear a new session's loading state.
            if refreshID == id {
                isLoading = false
                refreshID = nil
                refreshTask = nil
            }
        }
        while session == sessionID, !Task.isCancelled {
            // Wait for writes before asking for a snapshot of the server.
            for task in Array(writes.values) { _ = await task.result }
            guard session == sessionID, !Task.isCancelled else { return }
            if !writes.isEmpty { continue }
            let startRevision = revision
            let diskRevision = cache.load(sessionID: cacheSessionID)?.revision
            do {
                async let fetched = api.fetchAllBookmarks()
                async let tags = api.fetchTags()
                let (list, names) = try await (fetched, tags)
                guard session == sessionID, !Task.isCancelled else { return }
                // A write during the GET makes this snapshot obsolete, even
                // if the write has already completed. Fetch again after it.
                if revision != startRevision { continue }
                let snapshot = CacheSnapshot(bookmarks: list, tags: names, syncedAt: .now,
                                             serverHost: cache.load(sessionID: cacheSessionID)?.serverHost,
                                             sessionID: cacheSessionID)
                switch cache.replace(snapshot, ifUnchangedSince: diskRevision) {
                case .changed:
                    loadFromCache()
                    continue
                case .invalidSession: return
                case .saved, .unavailable: break
                }
                confirmed = list
                knownTags = names
                lastSync = .now
                isOffline = false
                loadError = nil
                hasLoadedOnce = true
                publishBookmarks()
                WidgetCenter.shared.reloadAllTimelines()
                return
            } catch {
                guard session == sessionID, !Task.isCancelled else { return }
                if error is CancellationError { return }
                if revision != startRevision { continue }
                if let error = error as? LinkdingError {
                    if error.isNetwork {
                        isOffline = true
                        if bookmarks.isEmpty { loadError = error }
                    } else {
                        isOffline = false
                        loadError = error
                    }
                } else {
                    if bookmarks.isEmpty { loadError = .unreachable(host: "") }
                    isOffline = true
                }
                return
            }
        }
    }

    private func enqueue(_ operation: Write, fromForm: Bool = false) -> Task<Bookmark?, Error> {
        guard let api else { return Task { throw CancellationError() } }
        let session = sessionID
        let write = PendingWrite(operation: operation)
        // Different known bookmarks remain independent. A create waits for
        // all earlier writes, and later writes wait for it: linkding can
        // return an existing ID when the URL is already saved.
        let predecessors = pending.filter {
            $0.operation.bookmarkID == nil || operation.bookmarkID == nil
                || $0.operation.bookmarkID == operation.bookmarkID
        }.compactMap { writes[$0.id] }
        pending.append(write)
        revision += 1
        publishBookmarks()
        let task = Task<Bookmark?, Error> {
            for predecessor in predecessors { _ = await predecessor.result }
            do {
                try Task.checkCancellation()
                guard session == self.sessionID else { throw CancellationError() }
                let saved = try await operation.send(to: api)
                try Task.checkCancellation()
                guard session == self.sessionID else { throw CancellationError() }
                if let saved {
                    if let index = self.confirmed.firstIndex(where: { $0.id == saved.id }) {
                        self.confirmed[index] = saved
                    } else {
                        self.confirmed.insert(saved, at: 0)
                    }
                    for tag in saved.tagNames where !self.knownTags.contains(tag) { self.knownTags.append(tag) }
                } else {
                    operation.apply(to: &self.confirmed, at: write.date)
                }
                self.finish(write)
                self.persist(operation, saved: saved)
                if fromForm {
                    self.successCount += 1
                    self.show(String(localized: "Enregistré"))
                }
                return saved
            } catch {
                guard session == self.sessionID else { throw CancellationError() }
                // Remove only this intent, then replay later ones on the last
                // confirmed state. An older failure cannot undo a newer tap.
                self.finish(write)
                if !(error is CancellationError), !fromForm {
                    if case .delete = operation { self.show(String(localized: "Suppression impossible")) }
                    else { self.show(String(localized: "Modification impossible")) }
                }
                throw error
            }
        }
        writes[write.id] = task
        return task
    }

    private func finish(_ write: PendingWrite) {
        pending.removeAll { $0.id == write.id }
        writes[write.id] = nil
        revision += 1
        publishBookmarks()
    }

    private func publishBookmarks() {
        var list = confirmed
        for write in pending { write.operation.apply(to: &list, at: write.date) }
        bookmarks = list
    }

    private func persist(_ operation: Write, saved: Bookmark?) {
        // Read/modify/write is one interprocess transaction. An extension's
        // unrelated bookmark must survive an app mutation with an old list.
        if let snapshot = cache.update(sessionID: cacheSessionID, { snapshot in
            if let saved { snapshot.upsert(saved) }
            else { operation.apply(to: &snapshot.bookmarks, at: .now) }
        }) {
            confirmed = snapshot.bookmarks
            knownTags = snapshot.tags
            publishBookmarks()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor
    private final class FormAPI: LinkdingAPI {
        let store: BookmarkStore
        let api: LinkdingAPI
        let sessionID: UUID

        init(store: BookmarkStore, api: LinkdingAPI, sessionID: UUID) {
            self.store = store
            self.api = api
            self.sessionID = sessionID
        }

        func testConnection() async throws -> Int { try await api.testConnection() }
        func fetchAllBookmarks() async throws -> [Bookmark] { try await api.fetchAllBookmarks() }
        func fetchTags() async throws -> [String] { try await api.fetchTags() }
        func check(url: String) async throws -> CheckResponse { try await api.check(url: url) }

        private func save(_ operation: Write) async throws -> Bookmark? {
            guard sessionID == store.sessionID else { throw CancellationError() }
            return try await store.enqueue(operation, fromForm: true).value
        }

        func create(_ draft: BookmarkDraft) async throws -> Bookmark {
            guard let saved = try await save(.create(draft)) else { throw LinkdingError.decoding }
            return saved
        }

        func update(id: Int, _ patch: BookmarkPatch) async throws -> Bookmark {
            guard let saved = try await save(.patch(id, patch)) else { throw LinkdingError.decoding }
            return saved
        }

        func setArchived(id: Int, _ archived: Bool) async throws { _ = try await save(.archive(id, archived)) }
        func delete(id: Int) async throws { _ = try await save(.delete(id)) }
    }
}
