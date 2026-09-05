import Foundation

/// Last synchronised state, written by the app, read by the widgets and used
/// as the offline list. One JSON file in the App Group container.
struct CacheSnapshot: Codable, Sendable {
    var bookmarks: [Bookmark]
    var tags: [String]
    var syncedAt: Date
    var serverHost: String?
}

final class BookmarkCache: @unchecked Sendable {
    static let shared = BookmarkCache(fileURL: AppGroup.containerURL.appendingPathComponent("bookmarks-cache.json"))

    let fileURL: URL
    private let queue = DispatchQueue(label: "app.letmiko.dingmark.cache")

    init(fileURL: URL) { self.fileURL = fileURL }

    func load() -> CacheSnapshot? {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(CacheSnapshot.self, from: data)
        }
    }

    func save(_ snapshot: CacheSnapshot) {
        queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    func clear() {
        queue.sync { try? FileManager.default.removeItem(at: fileURL) }
    }
}
