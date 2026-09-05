import Foundation
import Observation

/// Server address, token presence and connection test. The address lives in
/// the App Group defaults, the token in the Keychain.
@MainActor @Observable
final class Session {
    enum LoginFailure: Equatable {
        case invalidURL
        case unauthorized
        case untrustedCertificate(host: String)
        case unreachable(host: String)
    }

    private(set) var serverURL: URL?
    private(set) var hasToken: Bool
    private(set) var bookmarkCount: Int?
    let isDemo: Bool
    /// Credentials validated by `connect` but not yet applied to the UI.
    private var pendingLogin: (url: URL, count: Int)?

    var isConnected: Bool { isDemo || (serverURL != nil && hasToken) }
    var host: String? { isDemo ? DemoData.host : serverURL?.host() }

    init(demo: Bool = false) {
        isDemo = demo
        if demo {
            serverURL = URL(string: "https://\(DemoData.host)")
            hasToken = true
            bookmarkCount = DemoData.bookmarks.filter { !$0.isArchived }.count
        } else {
            serverURL = AppGroup.defaults.string(forKey: SettingsKey.serverURL).flatMap(URL.init(string:))
            hasToken = KeychainStore.readToken() != nil
            let count = AppGroup.defaults.integer(forKey: SettingsKey.bookmarkCount)
            bookmarkCount = count > 0 ? count : nil
        }
    }

    func makeAPI() -> LinkdingAPI? {
        if isDemo { return DemoLinkdingClient.shared }
        guard let serverURL, let token = KeychainStore.readToken() else { return nil }
        return LinkdingClient(baseURL: serverURL, token: token)
    }

    /// Tests the credentials against the server, persists them on success.
    func connect(urlString: String, token: String) async -> LoginFailure? {
        guard let url = URLDomain.normalizeServer(urlString) else { return .invalidURL }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return .unauthorized }
        let client = LinkdingClient(baseURL: url, token: trimmedToken)
        do {
            let count = try await client.testConnection()
            AppGroup.defaults.set(url.absoluteString, forKey: SettingsKey.serverURL)
            AppGroup.defaults.set(count, forKey: SettingsKey.bookmarkCount)
            KeychainStore.writeToken(trimmedToken)
            pendingLogin = (url, count)
            return nil
        } catch let error as LinkdingError {
            switch error {
            case .invalidURL: return .invalidURL
            case .unauthorized: return .unauthorized
            case .untrustedCertificate(let host): return .untrustedCertificate(host: host)
            case .unreachable(let host): return .unreachable(host: host)
            case .http, .decoding, .notConfigured: return .unreachable(host: client.host)
            }
        } catch {
            return .unreachable(host: client.host)
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

    /// Pins the certificate the last connection attempt rejected.
    func trustPendingCertificate(for host: String) {
        TrustStore.shared.pinPending(for: host)
    }

    func recordBookmarkCount(_ count: Int) {
        bookmarkCount = count
        AppGroup.defaults.set(count, forKey: SettingsKey.bookmarkCount)
    }

    func signOut() {
        KeychainStore.deleteToken()
        AppGroup.defaults.removeObject(forKey: SettingsKey.serverURL)
        AppGroup.defaults.removeObject(forKey: SettingsKey.bookmarkCount)
        BookmarkCache.shared.clear()
        serverURL = nil
        hasToken = false
        bookmarkCount = nil
    }
}
