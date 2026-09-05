import Foundation
import CryptoKit
import Security

/// Certificate fingerprints the user explicitly trusted (self-signed homelab
/// servers), plus the last rejected fingerprint per host so the login screen
/// can offer to trust it. Fingerprints are not secrets: they live in the App
/// Group defaults so the share extension and widgets share them.
final class TrustStore: @unchecked Sendable {
    static let shared = TrustStore(defaults: AppGroup.defaults)

    private let defaults: UserDefaults
    private let pinnedKey = "pinnedCertificateFingerprints"
    private let pendingKey = "pendingCertificateFingerprints"
    private let lock = NSLock()

    init(defaults: UserDefaults) { self.defaults = defaults }

    func pinnedFingerprint(for host: String) -> String? { read(pinnedKey)[host] }
    func pendingFingerprint(for host: String) -> String? { read(pendingKey)[host] }

    func pin(fingerprint: String, for host: String) {
        var pinned = read(pinnedKey)
        pinned[host] = fingerprint
        write(pinned, key: pinnedKey)
        var pending = read(pendingKey)
        pending.removeValue(forKey: host)
        write(pending, key: pendingKey)
    }

    /// Promotes the last rejected certificate of `host` to trusted.
    @discardableResult
    func pinPending(for host: String) -> Bool {
        guard let fp = pendingFingerprint(for: host) else { return false }
        pin(fingerprint: fp, for: host)
        return true
    }

    func setPending(fingerprint: String, for host: String) {
        var pending = read(pendingKey)
        pending[host] = fingerprint
        write(pending, key: pendingKey)
    }

    func unpin(host: String) {
        var pinned = read(pinnedKey)
        pinned.removeValue(forKey: host)
        write(pinned, key: pinnedKey)
    }

    private func read(_ key: String) -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private func write(_ value: [String: String], key: String) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(value, forKey: key)
    }
}

/// Accepts a server certificate the system rejects only when its SHA-256
/// fingerprint was pinned by the user. Otherwise the fingerprint is recorded
/// as pending and the default (failing) handling produces the
/// `serverCertificateUntrusted` error the UI turns into a "trust" offer.
final class ServerTrustDelegate: NSObject, URLSessionDelegate {
    private let store: TrustStore

    init(store: TrustStore) { self.store = store }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let host = challenge.protectionSpace.host
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let fingerprint = Self.leafFingerprint(of: trust) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if store.pinnedFingerprint(for: host) == fingerprint {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            store.setPending(fingerprint: fingerprint, for: host)
            completionHandler(.performDefaultHandling, nil)
        }
    }

    static func leafFingerprint(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        return SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }
}
