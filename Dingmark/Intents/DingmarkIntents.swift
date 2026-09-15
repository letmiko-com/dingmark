import AppIntents
import WidgetKit

/// Saves a link from Shortcuts, Siri or the Action button without opening
/// the app. Runs in the background; the server does the duplicate check.
struct AddBookmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter à Dingmark"
    static let description = IntentDescription("Enregistre un lien dans votre linkding avec vos tags par défaut. Une URL déjà enregistrée met à jour le favori existant.")
    static let openAppWhenRun = false

    @Parameter(title: "URL")
    var url: URL

    @Parameter(title: "Titre")
    var title: String?

    @Parameter(title: "Tags", default: [])
    var tags: [String]

    @Parameter(title: "Non lu")
    var unread: Bool?

    @Parameter(title: "Notes")
    var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Ajouter \(\.$url) à Dingmark") {
            \.$title
            \.$tags
            \.$unread
            \.$notes
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = Session()
        guard session.isConnected, let api = session.makeAPI() else { throw QuickSaveError.notConnected }
        let request = QuickSave.Request(url: url.absoluteString, title: title, tags: tags, unread: unread, notes: notes)
        do {
            let outcome = try await QuickSave.save(request, api: api, cache: .shared, cacheSessionID: session.cacheSessionID)
            WidgetCenter.shared.reloadAllTimelines()
            let name = outcome.bookmark.displayTitle
            return .result(dialog: outcome.updatedExisting
                ? IntentDialog("Favori mis à jour : \(name)")
                : IntentDialog("Enregistré dans Dingmark : \(name)"))
        } catch let error as LinkdingError {
            throw QuickSaveError.failed(error.userMessage)
        }
    }
}

/// Opens the add form, optionally prefilled: the natural Action button
/// shortcut when the link is about to be pasted.
struct NewBookmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Nouveau favori"
    static let description = IntentDescription("Ouvre Dingmark sur le formulaire d’ajout.")
    static let openAppWhenRun = true

    @Parameter(title: "URL")
    var url: URL?

    static var parameterSummary: some ParameterSummary {
        Summary("Nouveau favori \(\.$url)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        var components = URLComponents()
        components.scheme = "dingmark"
        components.host = "add"
        if let url { components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)] }
        guard let target = components.url else { throw QuickSaveError.notConnected }
        return .result(opensIntent: OpenURLIntent(target))
    }
}

enum QuickSaveError: Error, CustomLocalizedStringResourceConvertible {
    case notConnected
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConnected: "Dingmark n’est pas connecté. Ouvrez l’app pour connecter votre instance linkding."
        case .failed(let message): "Enregistrement impossible : \(message)"
        }
    }
}

/// Phrases for Siri and the Shortcuts app; both intents also appear in the
/// Action button picker. Translations live in AppShortcuts.xcstrings.
struct DingmarkShortcuts: AppShortcutsProvider {
    static let shortcutTileColor = ShortcutTileColor.teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddBookmarkIntent(),
            phrases: [
                "Ajouter à \(.applicationName)",
                "Enregistrer dans \(.applicationName)",
                "Ajouter ce lien à \(.applicationName)",
            ],
            shortTitle: "Ajouter à Dingmark",
            systemImageName: "bookmark.fill")
        AppShortcut(
            intent: NewBookmarkIntent(),
            phrases: [
                "Nouveau favori \(.applicationName)",
                "Ouvrir l’ajout dans \(.applicationName)",
            ],
            shortTitle: "Nouveau favori",
            systemImageName: "plus")
    }
}
