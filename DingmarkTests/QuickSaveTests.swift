import Foundation
import Testing
@testable import Dingmark

@Suite("QuickSave (intents)")
@MainActor
struct QuickSaveTests {
    private func makeEnvironment() throws -> (api: DemoLinkdingClient, cache: BookmarkCache, session: UUID, defaults: UserDefaults) {
        let api = DemoLinkdingClient(latency: .zero)
        let cache = BookmarkCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("quicksave-\(UUID()).json"))
        let session = cache.startSession(serverHost: "https://links.example.org")
        let defaults = try #require(UserDefaults(suiteName: "quicksave-\(UUID())"))
        defaults.set("inbox", forKey: SettingsKey.defaultTags)
        return (api, cache, session, defaults)
    }

    @Test("a new URL is created with the default tags, the given tags and the unread preference")
    func createsNewBookmark() async throws {
        let env = try makeEnvironment()
        defer { env.cache.clear() }
        let request = QuickSave.Request(url: "https://example.org/article", title: " Article ", tags: ["#Swift", "inbox"], notes: "à relire")
        let outcome = try await QuickSave.save(request, api: env.api, cache: env.cache, cacheSessionID: env.session, defaults: env.defaults)
        #expect(!outcome.updatedExisting)
        #expect(outcome.bookmark.url == "https://example.org/article")
        #expect(outcome.bookmark.title == "Article")
        #expect(outcome.bookmark.tagNames == ["inbox", "swift"])
        #expect(outcome.bookmark.unread == true)
        #expect(outcome.bookmark.notes == "à relire")
        #expect(env.cache.load(sessionID: env.session)?.bookmarks.first?.id == outcome.bookmark.id)
        let stored = try await env.api.fetchAllBookmarks()
        #expect(stored.contains { $0.url == "https://example.org/article" })
    }

    @Test("an explicit unread value beats the preference and an existing bookmark's flag")
    func explicitUnread() async throws {
        let env = try makeEnvironment()
        defer { env.cache.clear() }
        let created = try await QuickSave.save(QuickSave.Request(url: "https://example.org/read", unread: false),
                                               api: env.api, cache: env.cache, cacheSessionID: env.session, defaults: env.defaults)
        #expect(created.bookmark.unread == false)
        // restic.net exists in the demo data, read and tagged selfhosting/sécurité.
        let updated = try await QuickSave.save(QuickSave.Request(url: "https://restic.net", tags: ["backup"], unread: true),
                                               api: env.api, cache: env.cache, cacheSessionID: env.session, defaults: env.defaults)
        #expect(updated.updatedExisting)
        #expect(updated.bookmark.id == 5)
        #expect(updated.bookmark.unread == true)
        #expect(Set(updated.bookmark.tagNames) == ["selfhosting", "sécurité", "inbox", "backup"])
        #expect(try await env.api.fetchAllBookmarks().filter { $0.url == "https://restic.net" }.count == 1)
    }

    @Test("an existing URL keeps its flag when the request says nothing")
    func existingKeepsFlag() async throws {
        let env = try makeEnvironment()
        defer { env.cache.clear() }
        let outcome = try await QuickSave.save(QuickSave.Request(url: "https://restic.net"),
                                               api: env.api, cache: env.cache, cacheSessionID: env.session, defaults: env.defaults)
        #expect(outcome.updatedExisting)
        #expect(outcome.bookmark.unread == false)
    }

    @Test("an invalid URL is refused before any request")
    func invalidURL() async throws {
        let env = try makeEnvironment()
        defer { env.cache.clear() }
        await #expect(throws: LinkdingError.invalidURL) {
            _ = try await QuickSave.save(QuickSave.Request(url: "nope"), api: env.api, cache: env.cache, cacheSessionID: env.session, defaults: env.defaults)
        }
    }
}
