import Foundation

/// Storage shared by the app, the share extension and the widgets.
enum AppGroup {
    static let identifier = "group.app.letmiko.dingmark"

    static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

/// Keys of the App Group defaults (`@AppStorage(_, store: AppGroup.defaults)`).
enum SettingsKey {
    static let serverURL = "serverURL"
    static let cacheSessionID = "cacheSessionID"
    static let openLinksInApp = "openLinksInApp"
    static let unreadByDefault = "unreadByDefault"
    static let listDensity = "listDensity"
    static let defaultTags = "defaultTags"
    static let bookmarkCount = "bookmarkCount"
    static let demoMode = "demoMode"
    static let readerMode = "readerMode"
    static let markReadOnOpen = "markReadOnOpen"
    static let readingOrder = "readingOrder"
}

/// Reading preferences with their defaults, for code that has no
/// `@AppStorage` (the store, the intents).
enum ReadingSettings {
    /// Safari Reader is requested whenever the page offers it.
    static func readerMode(_ defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.object(forKey: SettingsKey.readerMode) as? Bool ?? true
    }

    /// Opening an unread bookmark marks it read.
    static func marksReadOnOpen(_ defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.object(forKey: SettingsKey.markReadOnOpen) as? Bool ?? true
    }
}

enum ListDensity: String, CaseIterable, Identifiable, Sendable {
    /// Title, domain, description on two lines, tags.
    case comfortable
    /// Title and domain only.
    case compact

    var id: String { rawValue }
}

/// Default tags are a comma separated string in defaults (`@AppStorage` has
/// no array support).
enum TagList {
    static func parse(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { TagNormalizer.normalize(String($0)) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func join(_ tags: [String]) -> String { tags.joined(separator: ",") }
}

enum TagNormalizer {
    /// linkding tags are single lowercase tokens; a leading `#` is tolerated.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("#") { s.removeFirst() }
        return s.replacingOccurrences(of: " ", with: "-")
    }
}
