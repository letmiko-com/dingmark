import SwiftUI
import UIKit
import WidgetKit

/// Compact form of the share extension: header (Cancel / mark + name /
/// Save), link card, tag field with the default tags, then toggles and notes
/// (visible in the large detent by scrolling).
struct ShareSheetView: View {
    let session: Session
    let sharedURL: String?
    let sharedTitle: String?
    var onFinish: () -> Void
    var onCancel: () -> Void

    @AppStorage(SettingsKey.defaultTags, store: AppGroup.defaults) private var defaultTagsRaw = ""
    @AppStorage(SettingsKey.unreadByDefault, store: AppGroup.defaults) private var unreadByDefault = true

    @State private var model: BookmarkFormModel?
    @State private var saving = false
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if !session.isConnected {
                ContentUnavailableView {
                    Label("Dingmark n’est pas connecté", systemImage: "server.rack")
                } description: {
                    Text("Ouvrez Dingmark et connectez votre instance linkding.")
                }
            } else if let model {
                form(model)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .sensoryFeedback(.success, trigger: saved)
        .task {
            guard model == nil, session.isConnected, let api = session.makeAPI() else { return }
            let snapshot = BookmarkCache.shared.load()
            let usage = BookmarkFilter.tagCounts(snapshot?.bookmarks ?? [])
            let created = BookmarkFormModel(
                api: api,
                mode: .create,
                suggestionPool: TagSuggestions.pool(usage: usage, known: snapshot?.tags ?? []),
                defaultTags: TagList.parse(defaultTagsRaw),
                unreadByDefault: unreadByDefault,
                prefillURL: sharedURL,
                prefillTitle: sharedTitle)
            model = created
            created.urlDidChange()
        }
    }

    private var header: some View {
        HStack {
            Button("Annuler", action: onCancel)
            Spacer()
            HStack(spacing: 8) {
                DingmarkIcon(size: 24)
                Text("Dingmark").font(.body.weight(.semibold))
            }
            Spacer()
            Button {
                save()
            } label: {
                if saving {
                    ProgressView().controlSize(.small)
                } else {
                    Text(model?.savesExisting == true ? "Mettre à jour" : "Enregistrer").fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(model?.canSave != true || saving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func form(_ model: BookmarkFormModel) -> some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 12) {
                if model.existing != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Déjà enregistré").fontWeight(.medium)
                        Text("· les modifications s’appliquent au favori existant").foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }

                card {
                    HStack(alignment: .top, spacing: 12) {
                        FaviconView(bookmark: Bookmark(id: 0, url: model.url), size: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Titre", text: $model.title)
                                .font(.body.weight(.semibold))
                                .opacity(model.isFetching ? 0.4 : 1)
                            TextField("URL", text: $model.url)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: model.url) { _, _ in model.urlDidChange() }
                        }
                        if model.isFetching { ProgressView().controlSize(.small) }
                    }
                }

                card {
                    TagField(tags: $model.tags, suggestionPool: model.suggestionPool, autoTags: model.autoTags)
                }

                card {
                    VStack(spacing: 8) {
                        Toggle("Marquer non lu", isOn: $model.unread)
                        Divider()
                        Toggle("Partager sur l’instance", isOn: $model.shared)
                    }
                }

                card {
                    ZStack(alignment: .topLeading) {
                        if model.notes.isEmpty {
                            Text("Notes").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
                        }
                        TextEditor(text: $model.notes)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                    }
                }

                if let error = model.saveError {
                    Label(String(localized: "Enregistrement impossible : \(error.userMessage)"), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                Text("Tirez pour afficher plus d’options")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func save() {
        guard let model else { return }
        saving = true
        Task {
            defer { saving = false }
            guard let bookmark = try? await model.save() else { return }
            // Keep the app and the widgets in sync without waiting for the
            // next refresh.
            if var snapshot = BookmarkCache.shared.load() {
                snapshot.bookmarks.removeAll { $0.id == bookmark.id }
                snapshot.bookmarks.insert(bookmark, at: 0)
                for tag in bookmark.tagNames where !snapshot.tags.contains(tag) { snapshot.tags.append(tag) }
                BookmarkCache.shared.save(snapshot)
                WidgetCenter.shared.reloadAllTimelines()
            }
            saved = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .milliseconds(250))
            onFinish()
        }
    }
}
