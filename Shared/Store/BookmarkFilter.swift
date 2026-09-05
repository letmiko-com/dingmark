import Foundation

enum QuickFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, unread, archived, untagged
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

/// Pure list logic, shared by the store, the iPad sidebar and the tests.
enum BookmarkFilter {
    static func apply(_ bookmarks: [Bookmark], filter: QuickFilter, tag: String?, query: String) -> [Bookmark] {
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
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { matches($0, query: q) }
        }
        return list.sorted { $0.dateAdded > $1.dateAdded }
    }

    static func matches(_ bookmark: Bookmark, query: String) -> Bool {
        let haystack = [bookmark.displayTitle, bookmark.displayDescription, bookmark.url, bookmark.notes, bookmark.tagNames.joined(separator: " ")]
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return query.split(separator: " ").allSatisfy { term in
            haystack.contains { $0.range(of: term, options: options) != nil }
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
