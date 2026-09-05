import Foundation

/// URLSession client for a linkding server. One instance per (server, token).
final class LinkdingClient: LinkdingAPI, @unchecked Sendable {
    let baseURL: URL
    private let token: String
    private let session: URLSession
    private let trustDelegate: ServerTrustDelegate
    private let trustStore: TrustStore
    private let pageSize = 100
    /// Safety net against a runaway pagination loop.
    private let maxPages = 200

    var host: String { baseURL.host() ?? baseURL.absoluteString }

    init(baseURL: URL, token: String, trustStore: TrustStore = .shared, configuration: URLSessionConfiguration = .default) {
        self.baseURL = baseURL
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        self.trustStore = trustStore
        trustDelegate = ServerTrustDelegate(store: trustStore)
        session = URLSession(configuration: configuration, delegate: trustDelegate, delegateQueue: nil)
    }

    // MARK: LinkdingAPI

    func testConnection() async throws -> Int {
        let page: Page<Bookmark> = try await get("api/bookmarks/", query: [("limit", "1")])
        return page.count
    }

    func fetchAllBookmarks() async throws -> [Bookmark] {
        async let active = fetchPages(path: "api/bookmarks/")
        async let archived = fetchPages(path: "api/bookmarks/archived/")
        let activeList = try await active
        // Archived entries come from a dedicated endpoint; make sure the flag
        // is consistent whatever the server version answers.
        let archivedList = try await archived.map { bookmark in
            var b = bookmark
            b.isArchived = true
            return b
        }
        return activeList + archivedList
    }

    func fetchTags() async throws -> [String] {
        var names: [String] = []
        var offset = 0
        for _ in 0..<maxPages {
            let page: Page<TagDTO> = try await get("api/tags/", query: [("limit", "\(pageSize)"), ("offset", "\(offset)")])
            names += page.results.map(\.name)
            offset += page.results.count
            if page.next == nil || page.results.isEmpty { break }
        }
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func check(url: String) async throws -> CheckResponse {
        try await get("api/bookmarks/check/", query: [("url", url)])
    }

    func create(_ draft: BookmarkDraft) async throws -> Bookmark {
        let body = try LinkdingJSON.makeEncoder().encode(draft)
        let (data, _) = try await request("POST", "api/bookmarks/", body: body)
        return try decode(Bookmark.self, from: data)
    }

    func update(id: Int, _ patch: BookmarkPatch) async throws -> Bookmark {
        let body = try LinkdingJSON.makeEncoder().encode(patch)
        let (data, _) = try await request("PATCH", "api/bookmarks/\(id)/", body: body)
        return try decode(Bookmark.self, from: data)
    }

    func setArchived(id: Int, _ archived: Bool) async throws {
        _ = try await request("POST", "api/bookmarks/\(id)/\(archived ? "archive" : "unarchive")/")
    }

    func delete(id: Int) async throws {
        _ = try await request("DELETE", "api/bookmarks/\(id)/")
    }

    // MARK: Plumbing

    private func fetchPages(path: String) async throws -> [Bookmark] {
        var items: [Bookmark] = []
        var offset = 0
        for _ in 0..<maxPages {
            let page: Page<Bookmark> = try await get(path, query: [("limit", "\(pageSize)"), ("offset", "\(offset)")])
            items += page.results
            offset += page.results.count
            if page.next == nil || page.results.isEmpty { break }
        }
        return items
    }

    private func get<T: Decodable>(_ path: String, query: [(String, String)] = []) async throws -> T {
        let (data, _) = try await request("GET", path, query: query)
        return try decode(T.self, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try LinkdingJSON.makeDecoder().decode(T.self, from: data) }
        catch { throw LinkdingError.decoding }
    }

    func makeURL(_ path: String, query: [(String, String)]) -> URL? {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard var comps = URLComponents(string: base + "/" + path) else { return nil }
        if !query.isEmpty {
            // Encode values strictly (`+`, `&`, `=` inside a bookmarked URL
            // must survive the round trip to /check/).
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            comps.percentEncodedQueryItems = query.map { key, value in
                URLQueryItem(name: key, value: value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
            }
        }
        return comps.url
    }

    @discardableResult
    private func request(_ method: String, _ path: String, query: [(String, String)] = [], body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = makeURL(path, query: query) else { throw LinkdingError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError where error.code == .cancelled {
            // The caller's task was cancelled (sign out, view gone): not a
            // server problem, let the cancellation propagate.
            throw CancellationError()
        } catch let error as URLError {
            throw map(error)
        }
        guard let http = response as? HTTPURLResponse else { throw LinkdingError.unreachable(host: host) }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 401, 403: throw LinkdingError.unauthorized
        default: throw LinkdingError.http(status: http.statusCode)
        }
    }

    private func map(_ error: URLError) -> LinkdingError {
        switch error.code {
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected, .secureConnectionFailed:
            // Only a certificate the delegate actually rejected can be
            // trusted. Any other TLS failure (a plain-HTTP server reached
            // over https, a protocol mismatch) is reported as unreachable,
            // otherwise the login screen offers a pin that cannot help.
            return trustStore.pendingFingerprint(for: host) != nil ? .untrustedCertificate(host: host) : .unreachable(host: host)
        case .badURL, .unsupportedURL:
            return .invalidURL
        default:
            return .unreachable(host: host)
        }
    }
}
