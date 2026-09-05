import Testing
import Foundation
@testable import Dingmark

@Suite("Bookmark decoding")
struct BookmarkDecodingTests {
    static let pageJSON = """
    {
      "count": 123,
      "next": "http://127.0.0.1:8000/api/bookmarks/?limit=100&offset=100",
      "previous": null,
      "results": [
        {
          "id": 1,
          "url": "https://example.com",
          "title": "Example title",
          "description": "Example description",
          "notes": "Example notes",
          "web_archive_snapshot_url": "https://web.archive.org/web/20200926094623/https://example.com",
          "favicon_url": "http://127.0.0.1:8000/static/https_example_com.png",
          "preview_image_url": "http://127.0.0.1:8000/static/0ac5c53db923727765216a3a58e70522.jpg",
          "is_archived": false,
          "unread": true,
          "shared": false,
          "tag_names": ["tag1", "tag2"],
          "date_added": "2020-09-26T09:46:23.006313Z",
          "date_modified": "2020-09-26T16:01:14.275335Z"
        },
        {
          "id": 2,
          "url": "https://minimal.example",
          "title": null,
          "tag_names": [],
          "date_added": "2025-05-29T00:00:00Z",
          "date_modified": "2025-05-29T00:00:00Z"
        }
      ]
    }
    """

    @Test("the documented page decodes, optional fields default")
    func decodesPage() throws {
        let page = try LinkdingJSON.makeDecoder().decode(Page<Bookmark>.self, from: Data(Self.pageJSON.utf8))
        #expect(page.count == 123)
        #expect(page.next != nil)
        #expect(page.results.count == 2)
        let first = page.results[0]
        #expect(first.tagNames == ["tag1", "tag2"])
        #expect(first.unread)
        #expect(first.hasPreviewImage)
        #expect(first.domain == "example.com")
        let minimal = page.results[1]
        #expect(minimal.title == "")
        #expect(minimal.displayTitle == "https://minimal.example")
        #expect(minimal.isArchived == false)
        #expect(minimal.hasPreviewImage == false)
    }

    @Test("check response with a null bookmark")
    func decodesCheck() throws {
        let json = """
        {"bookmark": null, "metadata": {"title": "Scraped", "description": "Desc", "preview_image": null}, "auto_tags": ["veille"]}
        """
        let check = try LinkdingJSON.makeDecoder().decode(CheckResponse.self, from: Data(json.utf8))
        #expect(check.bookmark == nil)
        #expect(check.metadata?.title == "Scraped")
        #expect(check.autoTags == ["veille"])
    }

    @Test("drafts and patches are sent in snake_case, nil fields omitted")
    func encodesPayloads() throws {
        let draft = BookmarkDraft(url: "https://a.b", title: "T", unread: true, tagNames: ["x"])
        let draftJSON = try #require(String(data: LinkdingJSON.makeEncoder().encode(draft), encoding: .utf8))
        #expect(draftJSON.contains("\"tag_names\":[\"x\"]"))
        #expect(draftJSON.contains("\"is_archived\":false"))

        let patch = BookmarkPatch(unread: false)
        let patchJSON = try #require(String(data: LinkdingJSON.makeEncoder().encode(patch), encoding: .utf8))
        #expect(patchJSON == "{\"unread\":false}")
    }

    @Test("cache round trip keeps every field")
    func cacheRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = BookmarkCache(fileURL: dir.appendingPathComponent("cache.json"))
        let snapshot = CacheSnapshot(bookmarks: DemoData.bookmarks, tags: DemoData.tags, syncedAt: .now, serverHost: "h")
        cache.save(snapshot)
        let loaded = try #require(cache.load())
        #expect(loaded.bookmarks.map(\.id) == snapshot.bookmarks.map(\.id))
        #expect(loaded.bookmarks[0].tagNames == snapshot.bookmarks[0].tagNames)
        #expect(loaded.tags == snapshot.tags)
        cache.clear()
        #expect(cache.load() == nil)
    }
}
