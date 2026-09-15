import Testing
import Foundation
@testable import Dingmark

@Suite("BookmarkFilter")
struct BookmarkFilterTests {
    let fixtures = DemoData.bookmarks

    @Test("counts match the prototype: 9 active, 4 unread, 2 archived, 2 untagged")
    func counts() {
        let c = BookmarkFilter.counts(fixtures)
        #expect(c.all == 9)
        #expect(c.unread == 4)
        #expect(c.archived == 2)
        #expect(c.untagged == 2)
    }

    @Test("quick filters")
    func quickFilters() {
        #expect(BookmarkFilter.apply(fixtures, filter: .all, tag: nil, query: "").allSatisfy { !$0.isArchived })
        #expect(BookmarkFilter.apply(fixtures, filter: .unread, tag: nil, query: "").allSatisfy { $0.unread && !$0.isArchived })
        #expect(BookmarkFilter.apply(fixtures, filter: .archived, tag: nil, query: "").map(\.id).sorted() == [9, 10])
        #expect(BookmarkFilter.apply(fixtures, filter: .untagged, tag: nil, query: "").map(\.id).sorted() == [7, 11])
    }

    @Test("tag filter is case and hash insensitive, and excludes archived")
    func tagFilter() {
        let selfhosting = BookmarkFilter.apply(fixtures, filter: .all, tag: "#Selfhosting", query: "")
        #expect(selfhosting.map(\.id).sorted() == [1, 2, 5])
    }

    @Test("search ignores case and diacritics, every term must match")
    func search() {
        #expect(BookmarkFilter.apply(fixtures, filter: .all, tag: nil, query: "reseau").map(\.id).sorted() == [1])
        #expect(BookmarkFilter.apply(fixtures, filter: .all, tag: nil, query: "TAILSCALE ssh").map(\.id) == [1])
        #expect(BookmarkFilter.apply(fixtures, filter: .all, tag: nil, query: "tailscale immich").isEmpty)
        #expect(BookmarkFilter.apply(fixtures, filter: .all, tag: nil, query: "restic.net").map(\.id) == [5])
    }

    @Test("newest first")
    func sorting() {
        let list = BookmarkFilter.apply(fixtures, filter: .all, tag: nil, query: "")
        #expect(list.first?.id == 1)
        #expect(zip(list, list.dropFirst()).allSatisfy { $0.dateAdded >= $1.dateAdded })
    }

    @Test("reading queue: unread active bookmarks, oldest first by default")
    func readingList() {
        let oldest = BookmarkFilter.readingList(fixtures, order: .oldestFirst)
        #expect(oldest.allSatisfy { $0.unread && !$0.isArchived })
        #expect(oldest.map(\.id) == [7, 4, 2, 1])
        #expect(BookmarkFilter.readingList(fixtures, order: .newestFirst).map(\.id) == [1, 2, 4, 7])
        var archivedUnread = fixtures[0]
        archivedUnread.isArchived = true
        #expect(!BookmarkFilter.readingList([archivedUnread], order: .oldestFirst).contains { $0.id == archivedUnread.id })
    }

    @Test("tag usage counts, most used first")
    func tagCounts() {
        let counts = BookmarkFilter.tagCounts(fixtures)
        #expect(counts.first?.name == "selfhosting")
        #expect(counts.first?.count == 4)
        #expect(counts.contains { $0.name == "docker" && $0.count == 2 })
    }

    @Test("active-only tag counts match what a tag filter shows")
    func activeTagCounts() {
        let counts = BookmarkFilter.tagCounts(fixtures, includeArchived: false)
        // Caddy (archived) carries selfhosting, réseau and docker; "lecture" only exists on an archived bookmark.
        #expect(counts.first { $0.name == "selfhosting" }?.count == BookmarkFilter.apply(fixtures, filter: .all, tag: "selfhosting", query: "").count)
        #expect(counts.first { $0.name == "docker" }?.count == 1)
        #expect(!counts.contains { $0.name == "lecture" })
        for (name, count) in counts {
            #expect(BookmarkFilter.apply(fixtures, filter: .all, tag: name, query: "").count == count)
        }
    }
}
