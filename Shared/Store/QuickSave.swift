import Foundation

/// Saving a link without showing the form: App Intents (Shortcuts, Siri,
/// the Action button). Same rules as the form: duplicate check first, an
/// existing URL is updated instead of duplicated, default tags added, the
/// confirmed bookmark merged into the shared cache.
enum QuickSave {
    struct Request: Equatable, Sendable {
        var url: String
        var title: String? = nil
        var tags: [String] = []
        /// Explicit value wins over the "unread by default" preference and,
        /// for an existing bookmark, over its stored flag.
        var unread: Bool? = nil
        var notes: String? = nil
    }

    struct Outcome: Equatable, Sendable {
        let bookmark: Bookmark
        let updatedExisting: Bool
    }

    @MainActor
    static func save(_ request: Request, api: LinkdingAPI, cache: BookmarkCache, cacheSessionID: UUID?,
                     defaults: UserDefaults = AppGroup.defaults) async throws -> Outcome {
        let defaultTags = TagList.parse(defaults.string(forKey: SettingsKey.defaultTags) ?? "")
        let unreadByDefault = defaults.object(forKey: SettingsKey.unreadByDefault) as? Bool ?? true
        let model = BookmarkFormModel(
            api: api,
            mode: .create,
            suggestionPool: [],
            defaultTags: TagList.parse((defaultTags + request.tags).joined(separator: ",")),
            unreadByDefault: request.unread ?? unreadByDefault,
            prefillURL: request.url,
            prefillTitle: request.title?.trimmingCharacters(in: .whitespacesAndNewlines),
            checkDelay: .zero)
        if let notes = request.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            model.notes = notes
        }
        var saved = try await model.save()
        // The check copies an existing bookmark's flag into the model; an
        // explicit request still has the last word.
        if let unread = request.unread, saved.unread != unread {
            saved = try await api.update(id: saved.id, BookmarkPatch(unread: unread))
        }
        cache.update(sessionID: cacheSessionID) { $0.upsert(saved) }
        return Outcome(bookmark: saved, updatedExisting: model.savesExisting)
    }
}
