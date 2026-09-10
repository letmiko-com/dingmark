import Foundation

/// In-memory linkding for previews, screenshots and the `-demo` launch
/// argument. Behaves like the server: silent update of an existing URL,
/// metadata "scraping" from a small table, short latencies.
final class DemoLinkdingClient: LinkdingAPI, @unchecked Sendable {
    static let shared = DemoLinkdingClient()

    private let lock = NSLock()
    private var bookmarks: [Bookmark]
    private var tags: Set<String>
    private var nextID: Int
    private let latency: Duration

    private static let metadata: [String: (String, String)] = [
        "immich.app": ("Docker Compose — Immich", "Install Immich with Docker Compose."),
        "linkding.link": ("linkding", "Self-hosted bookmark manager that is designed to be minimal, fast, and easy to set up using Docker."),
        "github.com": ("GitHub", "Let’s build from here."),
        "developer.apple.com": ("Apple Developer Documentation", "Browse the latest developer documentation."),
    ]

    init(bookmarks: [Bookmark] = DemoData.bookmarks, tags: [String] = DemoData.tags, latency: Duration = .milliseconds(350)) {
        self.bookmarks = bookmarks
        self.tags = Set(tags).union(bookmarks.flatMap(\.tagNames))
        self.nextID = (bookmarks.map(\.id).max() ?? 0) + 1
        self.latency = latency
    }

    private func wait() async { try? await Task.sleep(for: latency) }

    func testConnection() async throws -> Int {
        await wait()
        return lock.withLock { bookmarks.filter { !$0.isArchived }.count }
    }

    func fetchAllBookmarks() async throws -> [Bookmark] {
        await wait()
        return lock.withLock { bookmarks }
    }

    func fetchTags() async throws -> [String] {
        await wait()
        return lock.withLock { tags.sorted() }
    }

    func check(url: String) async throws -> CheckResponse {
        await wait()
        let domain = URLDomain.domain(of: url)
        // Like the server: a duplicate is the same URL, not the same site.
        let existing = lock.withLock { bookmarks.first { $0.url == url } }
        let meta = Self.metadata[domain].map { CheckResponse.Metadata(title: $0.0, description: $0.1, previewImage: nil) }
            ?? CheckResponse.Metadata(title: domain.capitalized, description: nil, previewImage: nil)
        let auto = domain.contains("docker") || domain.contains("immich") ? ["docker"] : []
        return CheckResponse(bookmark: existing, metadata: meta, autoTags: auto)
    }

    func create(_ draft: BookmarkDraft) async throws -> Bookmark {
        await wait()
        return lock.withLock {
            if let i = bookmarks.firstIndex(where: { $0.url == draft.url }) {
                apply(draft, to: &bookmarks[i])
                return bookmarks[i]
            }
            var b = Bookmark(id: nextID, url: draft.url)
            nextID += 1
            apply(draft, to: &b)
            b.dateAdded = .now
            bookmarks.insert(b, at: 0)
            return b
        }
    }

    func update(id: Int, _ patch: BookmarkPatch) async throws -> Bookmark {
        await wait()
        return try lock.withLock {
            guard let i = bookmarks.firstIndex(where: { $0.id == id }) else { throw LinkdingError.http(status: 404) }
            if let v = patch.url { bookmarks[i].url = v }
            if let v = patch.title { bookmarks[i].title = v }
            if let v = patch.description { bookmarks[i].description = v }
            if let v = patch.notes { bookmarks[i].notes = v }
            if let v = patch.isArchived { bookmarks[i].isArchived = v }
            if let v = patch.unread { bookmarks[i].unread = v }
            if let v = patch.shared { bookmarks[i].shared = v }
            if let v = patch.tagNames { bookmarks[i].tagNames = v; tags.formUnion(v) }
            bookmarks[i].dateModified = .now
            return bookmarks[i]
        }
    }

    func setArchived(id: Int, _ archived: Bool) async throws {
        await wait()
        lock.withLock {
            if let i = bookmarks.firstIndex(where: { $0.id == id }) {
                bookmarks[i].isArchived = archived
                bookmarks[i].dateModified = .now
            }
        }
    }

    func delete(id: Int) async throws {
        await wait()
        lock.withLock { bookmarks.removeAll { $0.id == id } }
    }

    private func apply(_ draft: BookmarkDraft, to b: inout Bookmark) {
        if !draft.title.isEmpty { b.title = draft.title }
        if !draft.description.isEmpty { b.description = draft.description }
        if !draft.notes.isEmpty { b.notes = draft.notes }
        if draft.isArchived { b.isArchived = true }
        b.unread = draft.unread
        if draft.shared { b.shared = true }
        if !draft.tagNames.isEmpty { b.tagNames = draft.tagNames }
        b.dateModified = .now
        tags.formUnion(draft.tagNames)
    }
}
