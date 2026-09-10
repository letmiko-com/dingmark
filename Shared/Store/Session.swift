import Foundation
import Observation

/// Server address, token presence and connection test. The address lives in
/// the App Group defaults, the token in the Keychain.
@MainActor @Observable
final class Session {
    enum LoginFailure: Equatable {
        case invalidURL
        case unauthorized
        case credentialStorage
        case untrustedCertificate(CertificateReview)
        case unreachable(host: String)
    }

    struct CertificateReview: Equatable {
        let host: String
        let fingerprint: String
        let previousFingerprint: String?
    }

    private let defaults: UserDefaults
    private let tokenStorage: TokenStorage
    private let cache: BookmarkCache
    private let trustStore: TrustStore
    private let apiFactory: (URL, String) -> LinkdingAPI
    private var loginGeneration = UUID()
    private(set) var cacheSessionID: UUID?
    private(set) var serverURL: URL?
    private(set) var hasToken: Bool
    private(set) var bookmarkCount: Int?
    let isDemo: Bool
    /// Credentials validated by `connect` but not yet applied to the UI.
    private var pendingLogin: (url: URL, count: Int)?

    var isConnected: Bool { isDemo || (serverURL != nil && hasToken) }
    var host: String? { isDemo ? DemoData.host : serverURL?.host() }

    init(demo: Bool = false, defaults: UserDefaults = AppGroup.defaults,
         tokenStorage: TokenStorage = KeychainTokenStorage(), cache: BookmarkCache = .shared,
         trustStore: TrustStore = .shared, apiFactory: ((URL, String) -> LinkdingAPI)? = nil) {
        self.defaults = defaults
        self.tokenStorage = tokenStorage
        self.cache = cache
        self.trustStore = trustStore
        self.apiFactory = apiFactory ?? { LinkdingClient(baseURL: $0, token: $1, trustStore: trustStore) }
        isDemo = demo
        if demo {
            serverURL = URL(string: "https://\(DemoData.host)")
            hasToken = true
            bookmarkCount = DemoData.bookmarks.filter { !$0.isArchived }.count
        } else {
            serverURL = defaults.string(forKey: SettingsKey.serverURL).flatMap(URL.init(string:))
            hasToken = tokenStorage.readToken() != nil
            let count = defaults.integer(forKey: SettingsKey.bookmarkCount)
            bookmarkCount = count > 0 ? count : nil
            if let serverURL, hasToken {
                if let stored = defaults.string(forKey: SettingsKey.cacheSessionID).flatMap(UUID.init(uuidString:)) {
                    cacheSessionID = stored
                } else {
                    let id = cache.startSession(serverHost: serverURL.absoluteString, migrating: true)
                    defaults.set(id.uuidString, forKey: SettingsKey.cacheSessionID)
                    cacheSessionID = id
                }
            }
        }
    }

    func makeAPI() -> LinkdingAPI? {
        if isDemo { return DemoLinkdingClient.shared }
        guard let serverURL, let token = tokenStorage.readToken() else { return nil }
        return apiFactory(serverURL, token)
    }

    /// Tests the credentials against the server, persists them on success.
    func connect(urlString: String, token: String) async -> LoginFailure? {
        guard let url = URLDomain.normalizeServer(urlString) else { return .invalidURL }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return .unauthorized }
        let generation = UUID()
        loginGeneration = generation
        pendingLogin = nil
        let client = apiFactory(url, trimmedToken)
        do {
            let count = try await client.testConnection()
            guard generation == loginGeneration, !Task.isCancelled else { return .unreachable(host: url.host() ?? "") }
            guard tokenStorage.writeToken(trimmedToken) else { return .credentialStorage }
            let id = cache.startSession(serverHost: url.absoluteString)
            cacheSessionID = id
            defaults.set(id.uuidString, forKey: SettingsKey.cacheSessionID)
            defaults.set(url.absoluteString, forKey: SettingsKey.serverURL)
            defaults.set(count, forKey: SettingsKey.bookmarkCount)
            pendingLogin = (url, count)
            return nil
        } catch let error as LinkdingError {
            switch error {
            case .invalidURL: return .invalidURL
            case .unauthorized: return .unauthorized
            case .untrustedCertificate(let host):
                guard let fingerprint = trustStore.pendingFingerprint(for: host) else { return .unreachable(host: host) }
                return .untrustedCertificate(CertificateReview(host: host, fingerprint: fingerprint,
                                                               previousFingerprint: trustStore.pinnedFingerprint(for: host)))
            case .unreachable(let host): return .unreachable(host: host)
            case .http, .decoding, .incompletePagination, .notConfigured: return .unreachable(host: url.host() ?? "")
            }
        } catch {
            return .unreachable(host: url.host() ?? "")
        }
    }

    /// Applies the credentials validated by the last successful `connect`.
    func commitLogin() {
        guard let pending = pendingLogin else { return }
        serverURL = pending.url
        bookmarkCount = pending.count
        hasToken = true
        pendingLogin = nil
    }

    /// Pin the exact fingerprint shown in the error card, even if another
    /// request has since recorded a different pending certificate.
    func trustCertificate(_ review: CertificateReview) {
        trustStore.pin(fingerprint: review.fingerprint, for: review.host)
    }

    func recordBookmarkCount(_ count: Int) {
        bookmarkCount = count
        if !isDemo { defaults.set(count, forKey: SettingsKey.bookmarkCount) }
    }

    func signOut() {
        loginGeneration = UUID()
        pendingLogin = nil
        tokenStorage.deleteToken()
        defaults.removeObject(forKey: SettingsKey.serverURL)
        defaults.removeObject(forKey: SettingsKey.bookmarkCount)
        defaults.removeObject(forKey: SettingsKey.cacheSessionID)
        cache.clear(sessionID: cacheSessionID)
        cacheSessionID = nil
        serverURL = nil
        hasToken = false
        bookmarkCount = nil
    }
}
