import SwiftUI

/// Builds the form model from the session and the store, then hands the
/// saved bookmark back to the store.
struct AddBookmarkSheet: View {
    var prefillURL: String?
    var prefillTitle: String?

    @Environment(Session.self) private var session
    @Environment(BookmarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.defaultTags, store: AppGroup.defaults) private var defaultTagsRaw = ""
    @AppStorage(SettingsKey.unreadByDefault, store: AppGroup.defaults) private var unreadByDefault = true

    @State private var model: BookmarkFormModel?

    var body: some View {
        Group {
            if let model {
                BookmarkFormView(model: model) { saved in
                    store.upsert(saved)
                    dismiss()
                } onCancel: {
                    dismiss()
                }
            } else {
                ProgressView()
            }
        }
        .task {
            guard model == nil, let api = session.makeAPI() else { return }
            model = BookmarkFormModel(
                api: api,
                mode: .create,
                suggestionPool: TagSuggestions.pool(usage: store.tagUsage, known: store.knownTags),
                defaultTags: TagList.parse(defaultTagsRaw),
                unreadByDefault: unreadByDefault,
                prefillURL: prefillURL,
                prefillTitle: prefillTitle)
            // A URL handed over by a deep link or the widget is checked
            // like a typed one: metadata, duplicate detection, auto tags.
            model?.urlDidChange()
        }
    }
}

struct EditBookmarkSheet: View {
    let bookmark: Bookmark

    @Environment(Session.self) private var session
    @Environment(BookmarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var model: BookmarkFormModel?

    var body: some View {
        Group {
            if let model {
                BookmarkFormView(model: model) { saved in
                    store.upsert(saved)
                    dismiss()
                } onCancel: {
                    dismiss()
                }
            } else {
                ProgressView()
            }
        }
        .task {
            guard model == nil, let api = session.makeAPI() else { return }
            model = BookmarkFormModel(
                api: api,
                mode: .edit(bookmark),
                suggestionPool: TagSuggestions.pool(usage: store.tagUsage, known: store.knownTags))
        }
    }
}
