import Foundation
import Testing
@testable import Dingmark

@Suite("AppRouter deep links")
@MainActor
struct AppRouterTests {
    @Test("dingmark://reading selects the reading tab")
    func reading() throws {
        let router = AppRouter()
        router.handle(try #require(URL(string: "dingmark://reading")))
        #expect(router.tab == .reading)
        #expect(router.addRequest == nil)
        #expect(router.pendingBookmarkID == nil)
    }

    @Test("dingmark://bookmark/<id> queues the detail on the bookmarks tab")
    func bookmark() throws {
        let router = AppRouter()
        router.tab = .settings
        router.handle(try #require(URL(string: "dingmark://bookmark/42")))
        #expect(router.tab == .bookmarks)
        #expect(router.pendingBookmarkID == 42)
    }

    @Test("dingmark://add carries the URL and title, other schemes are ignored")
    func add() throws {
        let router = AppRouter()
        router.handle(try #require(URL(string: "dingmark://add?url=https%3A%2F%2Fexample.org%2Fa%3Fb%3D1&title=Hello")))
        #expect(router.tab == .bookmarks)
        #expect(router.addRequest?.url == "https://example.org/a?b=1")
        #expect(router.addRequest?.title == "Hello")
        let before = router.addRequest
        router.handle(try #require(URL(string: "https://example.org")))
        #expect(router.addRequest == before)
    }
}
