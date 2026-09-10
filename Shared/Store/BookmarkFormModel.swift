import Foundation
import Observation
import UniformTypeIdentifiers

/// State of the add / edit form, shared by the app sheet and the share
/// extension. The app injects the store's ordered API; the extension uses
/// its own client and merges the saved bookmark into the shared cache.
@MainActor @Observable
final class BookmarkFormModel {
    enum Mode: Equatable {
        case create
        case edit(Bookmark)
    }

    let mode: Mode
    var url: String { didSet { urlDidChange() } }
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
    private var checkTask: Task<CheckResponse, Error>?
    private var checkTarget: String?
    private var lastCheckedURL: String?
    private let checkDelay: Duration
    private var checkGeneration = 0
    /// What the last check wrote into the fields, so a new URL replaces it
    /// while anything the user typed or changed is kept.
    private var autoFilled = AutoFilled()
    private let defaultUnread: Bool

    private struct AutoFilled {
        var title: String?
        var description: String?
        var notes: String?
        var tags: [String] = []
        var unread: Bool?
        var shared: Bool?
    }

    init(api: LinkdingAPI, mode: Mode, suggestionPool: [String], defaultTags: [String] = [],
         unreadByDefault: Bool = false, prefillURL: String? = nil, prefillTitle: String? = nil,
         checkDelay: Duration = .milliseconds(500)) {
        self.api = api
        self.mode = mode
        self.suggestionPool = suggestionPool
        self.defaultUnread = unreadByDefault
        self.checkDelay = checkDelay
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
        guard !isEditing else { return }
        let target = normalizedURL
        guard target != checkTarget || (target != nil && checkTask == nil && lastCheckedURL == nil) else { return }
        checkTask?.cancel()
        checkTask = nil
        checkGeneration += 1
        checkTarget = target
        lastCheckedURL = nil
        existing = nil
        clearAutoFilled()
        autoTags = []
        saveError = nil
        isFetching = false
        guard let target else { return }
        let generation = checkGeneration
        let task = startCheck(target, delay: checkDelay)
        Task { [weak self] in
            do {
                let response = try await task.value
                self?.finishCheck(response, target: target, generation: generation)
            } catch {
                guard let self, generation == self.checkGeneration else { return }
                self.checkTask = nil
                self.isFetching = false
            }
        }
    }

    private func startCheck(_ target: String, delay: Duration = .zero) -> Task<CheckResponse, Error> {
        let api = api
        let task = Task {
            try await Task.sleep(for: delay)
            try Task.checkCancellation()
            return try await api.check(url: target)
        }
        checkTarget = target
        checkTask = task
        isFetching = true
        return task
    }

    private func finishCheck(_ response: CheckResponse, target: String, generation: Int) {
        guard generation == checkGeneration, normalizedURL == target, lastCheckedURL != target else { return }
        lastCheckedURL = target
        checkTask = nil
        isFetching = false
        applyCheck(response)
    }

    /// Saving also checks prefilled URLs and retries a failed background check.
    /// A cancelled or failed check is never interpreted as an absent bookmark.
    private func ensureChecked(_ target: String) async throws {
        guard lastCheckedURL != target else { return }
        let generation = checkGeneration
        let task = checkTask ?? startCheck(target)
        do {
            let response = try await task.value
            try Task.checkCancellation()
            guard generation == checkGeneration, normalizedURL == target else { throw CancellationError() }
            finishCheck(response, target: target, generation: generation)
        } catch {
            if generation == checkGeneration {
                checkTask = nil
                isFetching = false
            }
            throw error
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
    }

    /// Fills the empty fields from the server answer. Values written by a
    /// previous check are dropped first (unless the user changed them), so
    /// correcting the URL never leaves the title of another page behind.
    private func clearAutoFilled() {
        if title == autoFilled.title { title = "" }
        if description == autoFilled.description { description = "" }
        if notes == autoFilled.notes { notes = "" }
        tags.removeAll { autoFilled.tags.contains($0) }
        if unread == autoFilled.unread { unread = defaultUnread }
        if shared == autoFilled.shared { shared = false }
        autoFilled = AutoFilled()
    }

    func applyCheck(_ response: CheckResponse) {
        clearAutoFilled()
        if let found = response.bookmark {
            existing = found
            if title.isEmpty { title = found.displayTitle; autoFilled.title = title }
            if description.isEmpty { description = found.displayDescription; autoFilled.description = description }
            if notes.isEmpty { notes = found.notes; autoFilled.notes = notes }
            let added = found.tagNames.filter { !tags.contains($0) }
            tags += added
            autoFilled.tags = added
            unread = found.unread
            shared = found.shared
            autoFilled.unread = unread
            autoFilled.shared = shared
        } else {
            existing = nil
            if title.isEmpty, let scraped = response.metadata?.title, !scraped.isEmpty { title = scraped; autoFilled.title = scraped }
            if description.isEmpty, let scraped = response.metadata?.description, !scraped.isEmpty {
                description = scraped
                autoFilled.description = scraped
            }
        }
        autoTags = response.autoTags ?? []
    }

    func save() async throws -> Bookmark {
        guard !isSaving else { throw CancellationError() }
        guard let target = normalizedURL else { throw LinkdingError.invalidURL }
        isSaving = true
        defer { isSaving = false }
        do {
            if !isEditing { try await ensureChecked(target) }
            try Task.checkCancellation()
            guard normalizedURL == target else { throw CancellationError() }
            let cleanTags = TagList.parse(tags.joined(separator: ","))
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let saved: Bookmark
            switch mode {
            case .edit(let bookmark):
                saved = try await api.update(id: bookmark.id, patch(comparedTo: bookmark, url: target,
                    title: cleanTitle, description: cleanDescription, tags: cleanTags))
            case .create:
                if let existing {
                    saved = try await api.update(id: existing.id, patch(comparedTo: existing, url: target,
                        title: cleanTitle, description: cleanDescription, tags: cleanTags))
                } else {
                    saved = try await api.create(BookmarkDraft(
                        url: target, title: cleanTitle, description: cleanDescription, notes: notes,
                        unread: unread, shared: shared, tagNames: cleanTags))
                }
            }
            saveError = nil
            return saved
        } catch is CancellationError {
            saveError = nil
            throw CancellationError()
        } catch let error as LinkdingError {
            saveError = error
            throw error
        } catch {
            saveError = .unreachable(host: "")
            throw error
        }
    }

    private func patch(comparedTo original: Bookmark, url: String, title: String,
                       description: String, tags: [String]) -> BookmarkPatch {
        BookmarkPatch(
            url: url == original.url ? nil : url,
            title: title == (isEditing ? original.title : original.displayTitle) ? nil : title,
            description: description == (isEditing ? original.description : original.displayDescription) ? nil : description,
            notes: notes == original.notes ? nil : notes,
            unread: unread == original.unread ? nil : unread,
            shared: shared == original.shared ? nil : shared,
            tagNames: Set(tags) == Set(original.tagNames) ? nil : tags)
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
        case .incompletePagination: String(localized: "Synchronisation incomplète")
        case .notConfigured: String(localized: "Dingmark n’est pas connecté")
        }
    }
}
