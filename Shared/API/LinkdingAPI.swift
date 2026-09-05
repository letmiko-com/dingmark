import Foundation

/// The subset of the linkding REST API Dingmark uses. `LinkdingClient` talks
/// to a real server, `DemoLinkdingClient` serves the design fixtures.
protocol LinkdingAPI: Sendable {
    /// Validates the credentials and returns the number of active bookmarks.
    func testConnection() async throws -> Int
    /// Every bookmark, active and archived, across all pages.
    func fetchAllBookmarks() async throws -> [Bookmark]
    func fetchTags() async throws -> [String]
    func check(url: String) async throws -> CheckResponse
    func create(_ draft: BookmarkDraft) async throws -> Bookmark
    func update(id: Int, _ patch: BookmarkPatch) async throws -> Bookmark
    func setArchived(id: Int, _ archived: Bool) async throws
    func delete(id: Int) async throws
}
