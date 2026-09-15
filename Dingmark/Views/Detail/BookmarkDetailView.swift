import SwiftUI

struct BookmarkDetailView: View {
    let bookmarkID: Int

    @Environment(BookmarkStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(SettingsKey.openLinksInApp, store: AppGroup.defaults) private var openInApp = true
    @AppStorage(SettingsKey.readerMode, store: AppGroup.defaults) private var readerMode = true

    @State private var editing = false
    @State private var showSafari = false

    var body: some View {
        if let bookmark = store.bookmark(id: bookmarkID) {
            content(bookmark)
        } else {
            ContentUnavailableView("Favori supprimé", systemImage: "trash")
        }
    }

    private func content(_ bookmark: Bookmark) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let image = bookmark.previewImage {
                    ServerImage(url: image) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(Color(.tertiarySystemFill))
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, Metrics.screenMargin)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        FaviconView(bookmark: bookmark, size: 22)
                        Text(bookmark.domain).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(bookmark.displayTitle).font(.title2.bold()).textSelection(.enabled)
                    if !bookmark.displayDescription.isEmpty {
                        Text(bookmark.displayDescription).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if bookmark.hasTags {
                        FlowLayout(spacing: 6) {
                            ForEach(bookmark.tagNames, id: \.self) { tag in
                                Button {
                                    store.tagFilter = tag
                                    store.filter = .all
                                    // Pushed on a phone: go back to the
                                    // filtered list. In the split view the
                                    // detail column stays (dismiss would
                                    // clear the selection).
                                    if sizeClass != .regular { dismiss() }
                                } label: {
                                    TagChip(name: tag, style: .detail)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    Button {
                        open(bookmark)
                    } label: {
                        Label("Ouvrir", systemImage: "safari")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: Metrics.buttonHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    if let url = bookmark.resolvedURL {
                        Button {
                            UIPasteboard.general.url = url
                            store.show(String(localized: "URL copiée"))
                        } label: {
                            Image(systemName: "doc.on.doc").frame(width: Metrics.buttonHeight, height: Metrics.buttonHeight)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel(Text("Copier l’URL"))
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up").frame(width: Metrics.buttonHeight, height: Metrics.buttonHeight)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                    }
                }
                .padding(.horizontal, Metrics.screenMargin)

                if bookmark.hasNotes {
                    GroupCard(title: "Notes") {
                        MarkdownNotesView(notes: bookmark.notes)
                            .padding(16)
                    }
                }

                GroupCard {
                    VStack(spacing: 0) {
                        Toggle(isOn: Binding(get: { bookmark.unread }, set: { _ in store.toggleUnread(bookmark) })) {
                            Text("Non lu")
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        Divider().padding(.leading, 16)
                        metadataRow(Text("Partagé"), value: bookmark.shared ? Text("Oui") : Text("Non"))
                        Divider().padding(.leading, 16)
                        metadataRow(Text("Ajouté"), value: Text(bookmark.dateAdded, format: .dateTime.day().month(.abbreviated).year()))
                        Divider().padding(.leading, 16)
                        metadataRow(Text("Modifié"), value: Text(bookmark.dateModified, format: .dateTime.day().month(.abbreviated).year()))
                    }
                }

                Text(bookmark.url)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 32)
            }
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifier") { editing = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    BookmarkMenuItems(bookmark: bookmark) { dismiss() }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(Text("Plus d’actions"))
            }
        }
        .sheet(isPresented: $editing) {
            EditBookmarkSheet(bookmark: bookmark)
        }
        .fullScreenCover(isPresented: $showSafari) {
            if let url = bookmark.resolvedURL {
                SafariView(url: url, entersReader: readerMode) { showSafari = false }
                    .ignoresSafeArea()
            }
        }
    }

    private func metadataRow(_ label: Text, value: Text) -> some View {
        HStack {
            label
            Spacer()
            value.foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private func open(_ bookmark: Bookmark) {
        guard let url = bookmark.resolvedURL else { return }
        store.recordOpen(bookmark)
        if openInApp, url.scheme == "https" || url.scheme == "http" {
            showSafari = true
        } else {
            openURL(url)
        }
    }
}

/// Grey group with the 26 pt radius of iOS 27 inset grouped lists.
struct GroupCard<Content: View>: View {
    var title: LocalizedStringKey? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous))
        }
        .padding(.horizontal, Metrics.screenMargin)
    }
}
