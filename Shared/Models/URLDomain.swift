import Foundation

enum URLDomain {
    /// First web link found in free text (a URL copied with surrounding
    /// words, a message, a note). A link typed without a scheme comes back as
    /// typed, so the caller applies its own default (https), not the
    /// detector's http. `nil` when the text holds no web link.
    static func firstURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: whole) {
            guard let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { continue }
            let typed = (text as NSString).substring(with: match.range)
            return typed.contains("://") ? url.absoluteString : typed
        }
        return nil
    }

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
