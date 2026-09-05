import Testing
import Foundation
@testable import Dingmark

@Suite("LinkdingClient", .serialized)
struct LinkdingClientTests {
    private func makeClient() -> LinkdingClient {
        MockURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        return LinkdingClient(baseURL: URL(string: "https://links.example.org")!, token: " secret-token ",
                              trustStore: TrustStore(defaults: defaults), configuration: configuration)
    }

    private func bookmark(_ id: Int, archived: Bool = false) -> String {
        """
        {"id": \(id), "url": "https://site\(id).example", "title": "Site \(id)", "is_archived": \(archived),
         "unread": false, "shared": false, "tag_names": [], "date_added": "2025-01-0\(id)T00:00:00Z", "date_modified": "2025-01-0\(id)T00:00:00Z"}
        """
    }

    @Test("Authorization header, trailing slash, limit parameter")
    func testConnectionRequest() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            MockURLProtocol.json(200, "{\"count\": 248, \"next\": null, \"previous\": null, \"results\": []}", for: request)
        }
        let count = try await client.testConnection()
        #expect(count == 248)
        let request = try #require(MockURLProtocol.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token secret-token")
        // `URL.path` drops the trailing slash Django needs: compare the whole URL.
        #expect(request.url?.absoluteString == "https://links.example.org/api/bookmarks/?limit=1")
    }

    @Test("follows pagination and merges the archived endpoint")
    func pagination() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            let url = request.url!.absoluteString
            if url.hasPrefix("https://links.example.org/api/bookmarks/archived/?") {
                return MockURLProtocol.json(200, "{\"count\": 1, \"next\": null, \"previous\": null, \"results\": [\(self.bookmark(3))]}", for: request)
            }
            if url.hasPrefix("https://links.example.org/api/bookmarks/?"), url.contains("offset=0") {
                return MockURLProtocol.json(200, "{\"count\": 2, \"next\": \"x\", \"previous\": null, \"results\": [\(self.bookmark(1))]}", for: request)
            }
            if url.hasPrefix("https://links.example.org/api/bookmarks/?") {
                return MockURLProtocol.json(200, "{\"count\": 2, \"next\": null, \"previous\": null, \"results\": [\(self.bookmark(2))]}", for: request)
            }
            return MockURLProtocol.json(404, "{}", for: request)
        }
        let all = try await client.fetchAllBookmarks()
        #expect(all.map(\.id).sorted() == [1, 2, 3])
        #expect(all.first { $0.id == 3 }?.isArchived == true)
        #expect(all.first { $0.id == 1 }?.isArchived == false)
    }

    @Test("401 becomes unauthorized")
    func unauthorized() async {
        let client = makeClient()
        MockURLProtocol.handler = { request in MockURLProtocol.json(401, "{\"detail\": \"Invalid token.\"}", for: request) }
        await #expect(throws: LinkdingError.unauthorized) {
            _ = try await client.testConnection()
        }
    }

    @Test("check encodes the bookmarked URL strictly")
    func checkEncoding() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            MockURLProtocol.json(200, "{\"bookmark\": null, \"metadata\": {\"title\": \"T\"}, \"auto_tags\": []}", for: request)
        }
        _ = try await client.check(url: "https://example.com/a b?x=1&y=2+3")
        let request = try #require(MockURLProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://links.example.org/api/bookmarks/check/?url=https%3A%2F%2Fexample.com%2Fa%20b%3Fx%3D1%26y%3D2%2B3")
    }

    @Test("archive, unarchive and delete hit the documented endpoints")
    func mutations() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in MockURLProtocol.json(204, "", for: request) }
        try await client.setArchived(id: 7, true)
        try await client.setArchived(id: 7, false)
        try await client.delete(id: 7)
        let calls = MockURLProtocol.requests.map { "\($0.httpMethod!) \($0.url!.absoluteString)" }
        #expect(calls == ["POST https://links.example.org/api/bookmarks/7/archive/",
                          "POST https://links.example.org/api/bookmarks/7/unarchive/",
                          "DELETE https://links.example.org/api/bookmarks/7/"])
    }

    @Test("PATCH sends only the changed fields and decodes the bookmark")
    func patch() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            MockURLProtocol.json(200, self.bookmark(4), for: request)
        }
        let updated = try await client.update(id: 4, BookmarkPatch(unread: true))
        #expect(updated.id == 4)
        let request = try #require(MockURLProtocol.requests.first)
        #expect(request.httpMethod == "PATCH")
        let body = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        } ?? Data()
        #expect(String(data: body, encoding: .utf8) == "{\"unread\":true}")
    }
}
