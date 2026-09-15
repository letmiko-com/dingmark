import Foundation
import Testing
@testable import Dingmark

@Suite("Swipe configuration")
struct SwipeConfigurationTests {
    @Test("defaults: read on the right, archive first on the left, delete last and never a full swipe")
    func defaults() {
        let config = SwipeConfiguration.default
        #expect(config.leadingActions == [.toggleRead])
        #expect(config.trailingActions == [.archive, .toggleRead, .delete])
    }

    @Test("the chosen trailing action leads, the others follow, delete stays last unless chosen")
    func trailingOrder() {
        #expect(SwipeConfiguration(leading: .archive, trailing: .toggleRead).trailingActions == [.toggleRead, .archive, .delete])
        #expect(SwipeConfiguration(leading: .toggleRead, trailing: .delete).trailingActions == [.delete, .toggleRead, .archive])
        // Same action on both edges: still reachable everywhere, listed once per edge.
        let same = SwipeConfiguration(leading: .archive, trailing: .archive)
        #expect(same.leadingActions == [.archive])
        #expect(same.trailingActions == [.archive, .toggleRead, .delete])
    }

    @Test("none removes the edge entirely")
    func none() {
        #expect(SwipeConfiguration(leading: .none, trailing: .archive).leadingActions.isEmpty)
        #expect(SwipeConfiguration(leading: .toggleRead, trailing: .none).trailingActions.isEmpty)
    }

    @Test("loaded from the defaults, unknown or missing values fall back")
    func load() throws {
        let defaults = try #require(UserDefaults(suiteName: "swipe-\(UUID())"))
        #expect(SwipeConfiguration.load(defaults) == .default)
        defaults.set(SwipeAction.delete.rawValue, forKey: SettingsKey.swipeLeading)
        defaults.set("bogus", forKey: SettingsKey.swipeTrailing)
        let loaded = SwipeConfiguration.load(defaults)
        #expect(loaded.leading == .delete)
        #expect(loaded.trailing == .archive)
    }
}
