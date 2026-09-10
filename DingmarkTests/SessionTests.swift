import Foundation
import Testing
@testable import Dingmark

@Suite("Session credentials and certificate review")
@MainActor
struct SessionTests {
    private func fixture(api: LinkdingAPI = SessionTestAPI()) -> (Session, UserDefaults, MemoryTokens, BookmarkCache, TrustStore) {
        let defaults = UserDefaults(suiteName: "session-test-\(UUID())")!
        let cache = BookmarkCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("session-test-\(UUID()).json"))
        let tokens = MemoryTokens()
        let trust = TrustStore(defaults: defaults)
        let session = Session(defaults: defaults, tokenStorage: tokens, cache: cache, trustStore: trust, apiFactory: { _, _ in api })
        return (session, defaults, tokens, cache, trust)
    }

    @Test("a failed keychain write never publishes a connected session")
    func failedStorage() async {
        let (session, defaults, tokens, cache, _) = fixture()
        defer { cache.clear() }
        tokens.acceptWrites = false
        let failure = await session.connect(urlString: "https://example.org", token: UUID().uuidString)
        #expect(failure == .credentialStorage)
        session.commitLogin()
        #expect(!session.isConnected && !session.hasToken)
        #expect(session.makeAPI() == nil)
        #expect(defaults.string(forKey: SettingsKey.serverURL) == nil)
        #expect(defaults.string(forKey: SettingsKey.cacheSessionID) == nil)
        #expect(cache.load() == nil)
    }

    @Test("a failed replacement preserves the previous credentials and cache")
    func failedReplacement() async throws {
        let (session, defaults, tokens, cache, _) = fixture()
        defer { cache.clear() }
        let old = UUID().uuidString
        #expect(await session.connect(urlString: "https://old.example", token: old) == nil)
        session.commitLogin()
        let oldIdentity = try #require(session.cacheSessionID)
        cache.update(sessionID: oldIdentity) { $0.upsert(Bookmark(id: 1, url: "https://old.example/private")) }
        tokens.acceptWrites = false
        #expect(await session.connect(urlString: "https://new.example", token: UUID().uuidString) == .credentialStorage)
        session.commitLogin()
        #expect(tokens.readToken() == old)
        #expect(session.serverURL?.host() == "old.example")
        #expect(defaults.string(forKey: SettingsKey.serverURL) == "https://old.example")
        #expect(cache.load(sessionID: oldIdentity)?.bookmarks.map(\.id) == [1])
    }

    @Test("a successful login persists the token and scopes the shared cache")
    func successfulLogin() async throws {
        let (session, defaults, tokens, cache, _) = fixture()
        defer { cache.clear() }
        let generated = UUID().uuidString
        #expect(await session.connect(urlString: "https://example.org", token: generated) == nil)
        session.commitLogin()
        #expect(session.isConnected && session.makeAPI() != nil)
        #expect(tokens.readToken() == generated)
        let identity = try #require(session.cacheSessionID)
        #expect(defaults.string(forKey: SettingsKey.cacheSessionID) == identity.uuidString)
        #expect(cache.load(sessionID: identity)?.serverHost == "https://example.org")
    }

    @Test("signing out invalidates a login waiting to be committed")
    func pendingLoginSignOut() async {
        let (session, _, tokens, cache, _) = fixture()
        #expect(await session.connect(urlString: "https://example.org", token: UUID().uuidString) == nil)
        session.signOut()
        session.commitLogin()
        #expect(!session.isConnected)
        #expect(tokens.readToken() == nil && cache.load() == nil)
    }

    @Test("certificate approval pins the displayed fingerprint, not a later rejection")
    func exactCertificateApproval() async throws {
        let host = "example.org"
        let (session, _, _, cache, trust) = fixture(api: SessionTestAPI(failure: .untrustedCertificate(host: host)))
        defer { cache.clear() }
        let previous = String(repeating: "11", count: 32)
        let reviewed = String(repeating: "22", count: 32)
        let later = String(repeating: "33", count: 32)
        trust.pin(fingerprint: previous, for: host)
        trust.setPending(fingerprint: reviewed, for: host)
        let failure = await session.connect(urlString: "https://example.org", token: UUID().uuidString)
        guard case .untrustedCertificate(let review) = failure else { Issue.record("Missing certificate review"); return }
        #expect(review.fingerprint == reviewed && review.previousFingerprint == previous)
        trust.setPending(fingerprint: later, for: host)
        session.trustCertificate(review)
        #expect(trust.pinnedFingerprint(for: host) == reviewed)
        #expect(trust.pendingFingerprint(for: host) == later)
    }
}

private final class MemoryTokens: TokenStorage {
    var acceptWrites = true
    private var value: String?
    func readToken() -> String? { value }
    func writeToken(_ token: String) -> Bool {
        guard acceptWrites else { return false }
        value = token
        return true
    }
    func deleteToken() { value = nil }
}

private struct SessionTestAPI: LinkdingAPI {
    var failure: LinkdingError?
    func testConnection() async throws -> Int {
        if let failure { throw failure }
        return 12
    }
    func check(url: String) async throws -> CheckResponse { CheckResponse() }
    func fetchAllBookmarks() async throws -> [Bookmark] { [] }
    func fetchTags() async throws -> [String] { [] }
    func create(_ draft: BookmarkDraft) async throws -> Bookmark { throw LinkdingError.notConfigured }
    func update(id: Int, _ patch: BookmarkPatch) async throws -> Bookmark { throw LinkdingError.notConfigured }
    func setArchived(id: Int, _ archived: Bool) async throws {}
    func delete(id: Int) async throws {}
}
