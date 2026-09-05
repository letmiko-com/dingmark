import Foundation
import Observation
import WidgetKit

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// Bookmarks in memory, cache on disk, server behind. Every mutation is
/// optimistic: local state first, request after, silent rollback on failure.
@MainActor @Observable
final class BookmarkStore {
    var bookmarks: [Bookmark] = []
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
    private var refreshTask: Task<Void, Never>?

    init(api: LinkdingAPI?, cache: BookmarkCache = .shared) {
        self.api = api
        self.cache = cache
    }

    func configure(api: LinkdingAPI?) {
        self.api = api
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
        guard let snapshot = cache.load() else { return }
        bookmarks = snapshot.bookmarks
        knownTags = snapshot.tags
        lastSync = snapshot.syncedAt
        hasLoadedOnce = true
    }

    func refresh() async {
        guard let api else { return }
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let fetched = api.fetchAllBookmarks()
            async let tags = api.fetchTags()
            let (list, names) = try await (fetched, tags)
            bookmarks = list
            knownTags = names
            lastSync = .now
            isOffline = false
            loadError = nil
            hasLoadedOnce = true
            persist()
        } catch is CancellationError {
            return
        } catch let error as LinkdingError {
            if error.isNetwork {
                isOffline = true
                if bookmarks.isEmpty { loadError = error }
            } else {
                loadError = error
            }
        } catch {
            if Task.isCancelled { return }
            if bookmarks.isEmpty { loadError = .unreachable(host: "") }
            isOffline = true
        }
    }

    func reset() {
        bookmarks = []
        knownTags = []
        lastSync = nil
        loadError = nil
        isOffline = false
        hasLoadedOnce = false
        filter = .all
        tagFilter = nil
        query = ""
    }

    // MARK: Mutations

    func toggleUnread(_ bookmark: Bookmark) {
        guard let api else { return }
        let target = !bookmark.unread
        mutate(bookmark.id) { $0.unread = target }
        Task {
            do {
                let updated = try await api.update(id: bookmark.id, BookmarkPatch(unread: target))
                self.replace(updated)
            } catch {
                self.mutate(bookmark.id) { $0.unread = !target }
                self.show(String(localized: "Modification impossible"))
            }
        }
    }

    func setArchived(_ bookmark: Bookmark, _ archived: Bool) {
        guard let api else { return }
        destructiveCount += 1
        mutate(bookmark.id) { $0.isArchived = archived }
        show(archived ? String(localized: "Archivé") : String(localized: "Désarchivé"))
        Task {
            do {
                try await api.setArchived(id: bookmark.id, archived)
                self.persist()
            } catch {
                self.mutate(bookmark.id) { $0.isArchived = !archived }
                self.show(String(localized: "Modification impossible"))
            }
        }
    }

    func delete(_ bookmark: Bookmark) {
        guard let api else { return }
        destructiveCount += 1
        let removedIndex = bookmarks.firstIndex { $0.id == bookmark.id }
        bookmarks.removeAll { $0.id == bookmark.id }
        show(String(localized: "Supprimé"))
        Task {
            do {
                try await api.delete(id: bookmark.id)
                self.persist()
            } catch {
                if let removedIndex, removedIndex <= self.bookmarks.count {
                    self.bookmarks.insert(bookmark, at: removedIndex)
                } else {
                    self.bookmarks.append(bookmark)
                }
                self.show(String(localized: "Suppression impossible"))
            }
        }
    }

    /// Called after the form saved on the server.
    func upsert(_ bookmark: Bookmark) {
        replace(bookmark)
        for t in bookmark.tagNames where !knownTags.contains(t) { knownTags.append(t) }
        successCount += 1
        show(String(localized: "Enregistré"))
        persist()
    }

    func show(_ message: String) {
        toast = Toast(message: message)
    }

    // MARK: Private

    private func mutate(_ id: Int, _ change: (inout Bookmark) -> Void) {
        guard let i = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        change(&bookmarks[i])
        bookmarks[i].dateModified = .now
        persist()
    }

    private func replace(_ bookmark: Bookmark) {
        if let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[i] = bookmark
        } else {
            bookmarks.insert(bookmark, at: 0)
        }
        persist()
    }

    private func persist() {
        cache.save(CacheSnapshot(bookmarks: bookmarks, tags: knownTags, syncedAt: lastSync ?? .now, serverHost: nil))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
