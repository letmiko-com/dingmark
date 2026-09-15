import Foundation

/// What a row swipe does. One action per edge, chosen in the settings.
enum SwipeAction: String, CaseIterable, Identifiable, Sendable {
    case toggleRead, archive, delete, none
    var id: String { rawValue }

    /// The actions a row can carry, in display order: delete stays last.
    static let available: [SwipeAction] = [.toggleRead, .archive, .delete]
}

/// Leading (rightwards) and trailing (leftwards) swipe actions, like Mail's
/// swipe options. Defaults: read on the right, archive on the left; delete
/// is never a full swipe unless the user asks for it.
struct SwipeConfiguration: Equatable, Sendable {
    var leading: SwipeAction = .toggleRead
    var trailing: SwipeAction = .archive

    static let `default` = SwipeConfiguration()

    static func load(_ defaults: UserDefaults = AppGroup.defaults) -> SwipeConfiguration {
        SwipeConfiguration(
            leading: defaults.string(forKey: SettingsKey.swipeLeading).flatMap(SwipeAction.init(rawValue:)) ?? Self.default.leading,
            trailing: defaults.string(forKey: SettingsKey.swipeTrailing).flatMap(SwipeAction.init(rawValue:)) ?? Self.default.trailing)
    }

    /// Leading edge: the chosen action alone, triggered by a full swipe.
    var leadingActions: [SwipeAction] { leading == .none ? [] : [leading] }

    /// Trailing edge: the chosen action first (full swipe, outermost), then
    /// every other action so none becomes unreachable, delete last.
    var trailingActions: [SwipeAction] {
        guard trailing != .none else { return [] }
        return [trailing] + SwipeAction.available.filter { $0 != trailing }
    }
}
