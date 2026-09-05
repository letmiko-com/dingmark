import Foundation
import Observation
import UniformTypeIdentifiers

/// State of the add / edit form, shared by the app sheet and the share
/// extension. Talks to the API directly; the caller merges the saved bookmark
/// into its own store.
@MainActor @Observable
final class BookmarkFormModel {
    enum Mode: Equatable {
        case create
        case edit(Bookmark)
    }

    let mode: Mode
    var url: String
    var title: String
    var description: String
    var notes: String
    var tags: [String]
    var unread: Bool
    var shared: Bool

    /// Bookmark already stored for this URL (create mode): saving updates it.
    private(set) var existing: Bookmark?
    private(set) var isFetching = false
    private(set) var isSaving = false
    private(set) var autoTags: [String] = []
    var saveError: LinkdingError?

    /// Tags offered as suggestions, most used first.
    let suggestionPool: [String]

    private let api: LinkdingAPI
    private var checkTask: Task<Void, Never>?
    private var lastCheckedURL: String?

    init(api: LinkdingAPI, mode: Mode, suggestionPool: [String], defaultTags: [String] = [],
         unreadByDefault: Bool = false, prefillURL: String? = nil, prefillTitle: String? = nil) {
        self.api = api
        self.mode = mode
        self.suggestionPool = suggestionPool
        switch mode {
        case .create:
            url = prefillURL ?? ""
            title = prefillTitle ?? ""
            description = ""
            notes = ""
            tags = defaultTags
            unread = unreadByDefault
            shared = false
        case .edit(let bookmark):
            url = bookmark.url
            title = bookmark.title
            description = bookmark.description
            notes = bookmark.notes
            tags = bookmark.tagNames
            unread = bookmark.unread
            shared = bookmark.shared
        }
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// The URL as it will be sent: scheme added when missing, host required.
    var normalizedURL: String? {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard let parsed = URL(string: s), let host = parsed.host(), host.contains(".") || host == "localhost" else { return nil }
        return parsed.absoluteString
    }

    var canSave: Bool { !isSaving && normalizedURL != nil }
    var showsPasteButton: Bool { !isEditing && url.trimmingCharacters(in: .whitespaces).isEmpty }
    var savesExisting: Bool { !isEditing && existing != nil }

    /// Debounced `/api/bookmarks/check/`: metadata for the title and the
    /// description, plus the duplicate detection, from a single request.
    func urlDidChange() {
        checkTask?.cancel()
        guard !isEditing, let target = normalizedURL, target != lastCheckedURL else { return }
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await check(target)
        }
    }

    /// Paste button payload: a `public.url` item, or plain text that holds a
    /// link (URLs copied from Notes, Messages or a terminal are text).
    func paste(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        Task { @MainActor [weak self] in
            var pasted: String?
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
                if let url = item as? URL { pasted = url.absoluteString }
                else if let data = item as? Data { pasted = String(data: data, encoding: .utf8) }
            }
            if pasted == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
                if let text = item as? String { pasted = text }
                else if let data = item as? Data { pasted = String(data: data, encoding: .utf8) }
            }
            guard let self, let pasted else { return }
            self.applyPasted(pasted)
        }
    }

    /// Keeps the first link of the pasted text, or the text itself when it
    /// is a bare host (`links.example.org`), then runs the check.
    func applyPasted(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        url = URLDomain.firstURL(in: trimmed) ?? trimmed
        urlDidChange()
    }

    private func check(_ target: String) async {
        isFetching = true
        defer { isFetching = false }
        lastCheckedURL = target
        guard let response = try? await api.check(url: target), !Task.isCancelled else { return }
        if let found = response.bookmark {
            existing = found
            if title.isEmpty { title = found.displayTitle }
            if description.isEmpty { description = found.displayDescription }
            if notes.isEmpty { notes = found.notes }
            for tag in found.tagNames where !tags.contains(tag) { tags.append(tag) }
            unread = found.unread
            shared = found.shared
        } else {
            existing = nil
            if title.isEmpty, let scraped = response.metadata?.title { title = scraped }
            if description.isEmpty, let scraped = response.metadata?.description { description = scraped }
        }
        autoTags = response.autoTags ?? []
    }

    func save() async throws -> Bookmark {
        guard let target = normalizedURL else { throw LinkdingError.invalidURL }
        isSaving = true
        defer { isSaving = false }
        let cleanTags = TagList.parse(tags.joined(separator: ","))
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let saved: Bookmark
            switch mode {
            case .edit(let bookmark):
                saved = try await api.update(id: bookmark.id, BookmarkPatch(
                    url: target, title: cleanTitle, description: cleanDescription, notes: notes,
                    unread: unread, shared: shared, tagNames: cleanTags))
            case .create:
                if let existing {
                    saved = try await api.update(id: existing.id, BookmarkPatch(
                        url: target, title: cleanTitle, description: cleanDescription, notes: notes,
                        unread: unread, shared: shared, tagNames: cleanTags))
                } else {
                    saved = try await api.create(BookmarkDraft(
                        url: target, title: cleanTitle, description: cleanDescription, notes: notes,
                        unread: unread, shared: shared, tagNames: cleanTags))
                }
            }
            saveError = nil
            return saved
        } catch let error as LinkdingError {
            saveError = error
            throw error
        } catch {
            saveError = .unreachable(host: "")
            throw error
        }
    }
}

extension LinkdingError {
    /// Short user-facing sentence.
    var userMessage: String {
        switch self {
        case .invalidURL: String(localized: "URL invalide")
        case .unauthorized: String(localized: "Jeton refusé")
        case .untrustedCertificate: String(localized: "Certificat non reconnu")
        case .unreachable: String(localized: "Serveur injoignable")
        case .http(let status): String(localized: "Erreur serveur (\(status))")
        case .decoding: String(localized: "Réponse illisible")
        case .notConfigured: String(localized: "Dingmark n'est pas connecté")
        }
    }
}
