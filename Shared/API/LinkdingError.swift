import Foundation

enum LinkdingError: Error, Equatable, Sendable {
    /// The server address could not be turned into an origin.
    case invalidURL
    /// 401 or 403: the API token is refused.
    case unauthorized
    /// TLS failed: self-signed or unknown certificate. The leaf fingerprint
    /// is kept in `TrustStore` as pending so the user can pin it.
    case untrustedCertificate(host: String)
    /// Timeout, DNS failure, connection refused, or no network.
    case unreachable(host: String)
    /// Any other HTTP status.
    case http(status: Int)
    /// The body did not decode.
    case decoding
    /// Pagination stopped before the server reported its final page.
    case incompletePagination
    /// No server or token configured yet.
    case notConfigured

    var isNetwork: Bool {
        switch self {
        case .unreachable, .untrustedCertificate: return true
        default: return false
        }
    }
}
