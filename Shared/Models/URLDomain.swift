import Foundation

enum URLDomain {
    /// Host of a URL without a leading `www.`, or the raw string when it is
    /// not a URL. Used for the row subtitle and the favicon letter.
    static func domain(of urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        var host = URL(string: trimmed)?.host()
        if host == nil, let withScheme = URL(string: "https://" + trimmed) {
            host = withScheme.host()
        }
        guard var h = host?.lowercased(), !h.isEmpty else { return trimmed }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    /// Server URL as typed on the login screen, normalised to its origin.
    /// Accepts `links.example.org`, `https://links.example.org/bookmarks`.
    /// Plain HTTP is kept for homelab instances on the local network.
    static func normalizeServer(_ input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard var comps = URLComponents(string: s),
              let scheme = comps.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = comps.host, !host.isEmpty else { return nil }
        comps.scheme = scheme
        comps.query = nil
        comps.fragment = nil
        comps.user = nil
        comps.password = nil
        // Keep a sub-path prefix (reverse proxies mounting linkding under
        // /linkding) but drop linkding's own pages.
        var path = comps.path
        for suffix in ["/bookmarks", "/settings", "/api", "/tags", "/bundles"] {
            if let range = path.range(of: suffix) { path = String(path[..<range.lowerBound]) }
        }
        while path.hasSuffix("/") { path.removeLast() }
        comps.path = path
        return comps.url
    }
}
