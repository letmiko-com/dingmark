import Foundation
import Testing
@testable import Dingmark

@Suite("Shared cache transactions")
struct BookmarkCacheTests {
    private func cache() -> BookmarkCache {
        BookmarkCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("cache-test-\(UUID()).json"))
    }

    @Test("concurrent cache instances preserve every independent share")
    func concurrentWriters() throws {
        let cache = cache()
        defer { cache.clear() }
        let session = cache.startSession(serverHost: "https://example.org")
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            let writer = BookmarkCache(fileURL: cache.fileURL)
            writer.update(sessionID: session) { $0.upsert(Bookmark(id: index, url: "https://example.org/\(index)")) }
        }
        let snapshot = try #require(cache.load(sessionID: session))
        #expect(Set(snapshot.bookmarks.map(\.id)) == Set(0..<40))
    }

    @Test("late extension writes cannot recreate a signed-out cache")
    func signedOut() {
        let cache = cache()
        let session = cache.startSession(serverHost: "https://example.org")
        cache.clear(sessionID: session)
        let result = cache.update(sessionID: session) { $0.upsert(Bookmark(id: 1, url: "https://example.org")) }
        #expect(result == nil)
        #expect(cache.load() == nil)
    }

    @Test("different logins on the same server do not mix bookmark IDs")
    func accountChange() throws {
        let cache = cache()
        defer { cache.clear() }
        let old = cache.startSession(serverHost: "https://example.org")
        cache.update(sessionID: old) { $0.upsert(Bookmark(id: 1, url: "https://example.org/private")) }
        let current = cache.startSession(serverHost: "https://example.org")
        #expect(current != old)
        #expect(cache.update(sessionID: old, { $0.upsert(Bookmark(id: 1, url: "https://example.org/private")) }) == nil)
        cache.clear(sessionID: old)
        let snapshot = try #require(cache.load(sessionID: current))
        #expect(snapshot.bookmarks.isEmpty)
    }

    @Test("a whole-list write refuses a revision changed by another writer")
    func staleSnapshot() throws {
        let cache = cache()
        defer { cache.clear() }
        let session = cache.startSession(serverHost: "https://example.org")
        let old = try #require(cache.load(sessionID: session))
        cache.update(sessionID: session) { $0.upsert(Bookmark(id: 2, url: "https://example.org/shared")) }
        guard case .changed = cache.replace(old, ifUnchangedSince: old.revision) else {
            Issue.record("Stale snapshot overwrote a share")
            return
        }
        #expect(cache.load()?.bookmarks.map(\.id) == [2])
    }

    @Test("legacy caches migrate once and remain available to another process")
    func migration() throws {
        let cache = cache()
        defer { cache.clear() }
        cache.save(CacheSnapshot(bookmarks: [Bookmark(id: 5, url: "https://example.org")], tags: [], syncedAt: .now, serverHost: nil))
        let first = cache.startSession(serverHost: "https://example.org", migrating: true)
        let second = BookmarkCache(fileURL: cache.fileURL).startSession(serverHost: "https://example.org", migrating: true)
        #expect(first == second)
        #expect(cache.load(sessionID: first)?.bookmarks.map(\.id) == [5])
    }
}
