import Foundation

enum QuickFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, unread, archived, untagged
    var id: String { rawValue }
}

/// Order of the reading queue ("À lire"): a queue is consumed oldest first
/// by default, so nothing sinks and disappears.
enum ReadingOrder: String, CaseIterable, Identifiable, Sendable {
    case oldestFirst, newestFirst
    var id: String { rawValue }
}

struct FilterCounts: Equatable, Sendable {
    var all = 0
    var unread = 0
    var archived = 0
    var untagged = 0

    func value(for filter: QuickFilter) -> Int {
        switch filter {
        case .all: all
        case .unread: unread
        case .archived: archived
        case .untagged: untagged
        }
    }
}

/// linkding's search syntax: free terms, `#tag` restricts to a tag, and the
/// `!unread`, `!untagged`, `!shared`, `!unshared` commands. Other `!` words
/// are dropped, as linkding does.
struct SearchQuery: Equatable, Sendable {
    var terms: [String] = []
    var tags: [String] = []
    var unread = false
    var untagged = false
    var shared: Bool? = nil

    static func parse(_ raw: String) -> SearchQuery {
        var query = SearchQuery()
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let token = String(word)
            if token.hasPrefix("#") {
                let tag = TagNormalizer.normalize(token)
                if !tag.isEmpty, !query.tags.contains(tag) { query.tags.append(tag) }
            } else if token.hasPrefix("!") {
                switch token.lowercased() {
                case "!unread": query.unread = true
                case "!untagged": query.untagged = true
                case "!shared": query.shared = true
                case "!unshared": query.shared = false
                default: break
                }
            } else {
                query.terms.append(token)
            }
        }
        return query
    }

    var isEmpty: Bool { terms.isEmpty && tags.isEmpty && !unread && !untagged && shared == nil }

    func matches(_ bookmark: Bookmark) -> Bool {
        if unread, !bookmark.unread { return false }
        if untagged, !bookmark.tagNames.isEmpty { return false }
        if let shared, bookmark.shared != shared { return false }
        if !tags.isEmpty {
            let carried = Set(bookmark.tagNames.map(TagNormalizer.normalize))
            guard tags.allSatisfy(carried.contains) else { return false }
        }
        return terms.isEmpty || BookmarkFilter.matches(bookmark, terms: terms)
    }
}

/// Order of the library list, remembered per filter.
enum BookmarkSort: String, CaseIterable, Identifiable, Sendable {
    case newestAdded, oldestAdded, recentlyModified, title, domain
    var id: String { rawValue }

    func apply(_ list: [Bookmark]) -> [Bookmark] {
        switch self {
        case .newestAdded: list.sorted { $0.dateAdded > $1.dateAdded }
        case .oldestAdded: list.sorted { $0.dateAdded < $1.dateAdded }
        case .recentlyModified: list.sorted { $0.dateModified > $1.dateModified }
        case .title: list.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        case .domain:
            list.sorted {
                let order = $0.domain.localizedStandardCompare($1.domain)
                return order == .orderedSame ? $0.dateAdded > $1.dateAdded : order == .orderedAscending
            }
        }
    }
}

/// Pure list logic, shared by the store, the iPad sidebar and the tests.
enum BookmarkFilter {
    static func apply(_ bookmarks: [Bookmark], filter: QuickFilter, tag: String?, query: String,
                      sort: BookmarkSort = .newestAdded) -> [Bookmark] {
        var list: [Bookmark]
        switch filter {
        case .all: list = bookmarks.filter { !$0.isArchived }
        case .unread: list = bookmarks.filter { !$0.isArchived && $0.unread }
        case .archived: list = bookmarks.filter(\.isArchived)
        case .untagged: list = bookmarks.filter { !$0.isArchived && $0.tagNames.isEmpty }
        }
        if let tag, !tag.isEmpty {
            let wanted = TagNormalizer.normalize(tag)
            list = list.filter { $0.tagNames.contains { TagNormalizer.normalize($0) == wanted } }
        }
        let search = SearchQuery.parse(query)
        if !search.isEmpty {
            list = list.filter(search.matches)
        }
        return sort.apply(list)
    }

    static let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func matches(_ bookmark: Bookmark, query: String) -> Bool {
        SearchQuery.parse(query).matches(bookmark)
    }

    /// Every term must appear in one of the searched fields (title,
    /// description, URL, notes, tags).
    static func matches(_ bookmark: Bookmark, terms: [String]) -> Bool {
        let haystack = [bookmark.displayTitle, bookmark.displayDescription, bookmark.url, bookmark.notes, bookmark.tagNames.joined(separator: " ")]
        return terms.allSatisfy { term in
            haystack.contains { $0.range(of: term, options: searchOptions) != nil }
        }
    }

    /// The reading queue: active bookmarks still marked unread.
    static func readingList(_ bookmarks: [Bookmark], order: ReadingOrder) -> [Bookmark] {
        let queue = bookmarks.filter { !$0.isArchived && $0.unread }
        switch order {
        case .oldestFirst: return queue.sorted { $0.dateAdded < $1.dateAdded }
        case .newestFirst: return queue.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    static func counts(_ bookmarks: [Bookmark]) -> FilterCounts {
        var c = FilterCounts()
        for b in bookmarks {
            if b.isArchived { c.archived += 1; continue }
            c.all += 1
            if b.unread { c.unread += 1 }
            if b.tagNames.isEmpty { c.untagged += 1 }
        }
        return c
    }

    /// Tags with their usage count, most used first.
    static func tagCounts(_ bookmarks: [Bookmark], includeArchived: Bool = true) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for b in bookmarks where includeArchived || !b.isArchived {
            for t in b.tagNames { counts[t, default: 0] += 1 }
        }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
