import Foundation
import Darwin

/// Confirmed server values, shared by the app, share extension and widgets.
/// Optional identifiers keep caches written by earlier releases decodable.
struct CacheSnapshot: Codable, Sendable {
    var bookmarks: [Bookmark]
    var tags: [String]
    var syncedAt: Date
    var serverHost: String?
    var sessionID: UUID? = nil
    var revision: UUID? = nil

    mutating func upsert(_ bookmark: Bookmark) {
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            if bookmarks[index].dateModified <= bookmark.dateModified { bookmarks[index] = bookmark }
        } else {
            bookmarks.insert(bookmark, at: 0)
        }
        for tag in bookmark.tagNames where !tags.contains(tag) { tags.append(tag) }
    }
}

final class BookmarkCache: @unchecked Sendable {
    static let shared = BookmarkCache(fileURL: AppGroup.containerURL.appendingPathComponent("bookmarks-cache.json"))

    enum Replacement {
        case saved(CacheSnapshot)
        case changed
        case invalidSession
        case unavailable
    }

    let fileURL: URL
    private let queue = DispatchQueue(label: "app.letmiko.dingmark.cache")

    init(fileURL: URL) { self.fileURL = fileURL }

    func load(sessionID: UUID? = nil) -> CacheSnapshot? {
        withLockedFile {
            guard let snapshot = self.read(), sessionID == nil || snapshot.sessionID == sessionID else { return nil }
            return snapshot
        } ?? nil
    }

    /// Starts a login's cache. Migration adopts an older cache only once;
    /// concurrent app/extension launches receive the same identity.
    @discardableResult
    func startSession(id: UUID = UUID(), serverHost: String, migrating: Bool = false) -> UUID {
        withLockedFile {
            var snapshot = CacheSnapshot(bookmarks: [], tags: [], syncedAt: .now, serverHost: serverHost, sessionID: id)
            if migrating, let old = self.read(), old.serverHost == nil || old.serverHost == serverHost {
                snapshot = old
                snapshot.sessionID = old.sessionID ?? id
                snapshot.serverHost = serverHost
            }
            snapshot.revision = UUID()
            _ = self.write(snapshot)
            return snapshot.sessionID ?? id
        } ?? id
    }

    /// A whole-server refresh must not overwrite a share that completed while
    /// it was in flight. The caller retries when the disk revision changed.
    func replace(_ snapshot: CacheSnapshot, ifUnchangedSince revision: UUID?) -> Replacement {
        withLockedFile {
            let current = self.read()
            guard current?.sessionID == snapshot.sessionID else { return .invalidSession }
            guard current?.revision == revision else { return .changed }
            var updated = snapshot
            updated.revision = UUID()
            return self.write(updated) ? .saved(updated) : .unavailable
        } ?? .unavailable
    }

    /// Merge only the confirmed mutation into the latest cache, never an old
    /// whole list held by one process. Missing/changed sessions reject writes.
    @discardableResult
    func update(sessionID: UUID?, _ mutation: (inout CacheSnapshot) -> Void) -> CacheSnapshot? {
        withLockedFile {
            let current = self.read()
            guard current?.sessionID == sessionID else { return nil }
            var updated = current ?? CacheSnapshot(bookmarks: [], tags: [], syncedAt: .now, serverHost: nil)
            mutation(&updated)
            updated.revision = UUID()
            return self.write(updated) ? updated : nil
        } ?? nil
    }

    /// Used for fixtures and importing a snapshot; production mutations use
    /// update/replace to preserve other writers and session boundaries.
    func save(_ snapshot: CacheSnapshot) {
        _ = withLockedFile {
            var updated = snapshot
            updated.revision = UUID()
            return self.write(updated)
        }
    }

    func clear(sessionID: UUID? = nil) {
        _ = withLockedFile {
            guard sessionID == nil || self.read()?.sessionID == sessionID else { return }
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }

    private func read() -> CacheSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CacheSnapshot.self, from: data)
    }

    private func write(_ snapshot: CacheSnapshot) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch { return false }
    }

    /// The lock has a stable inode separate from the atomically replaced JSON.
    /// Every reader/writer cooperates, including other instances and processes.
    private func withLockedFile<T>(_ body: () -> T) -> T? {
        queue.sync {
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            } catch { return nil }
            let descriptor = open(fileURL.path + ".lock", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { return nil }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX) == 0 else { return nil }
            defer { flock(descriptor, LOCK_UN) }
            return body()
        }
    }
}
