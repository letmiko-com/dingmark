import SwiftUI

/// Main screen: large title, search drawer, quick filters, plain list with
/// swipe actions and context menu previews, floating add button.
struct BookmarkListScreen: View {
    @Environment(BookmarkStore.self) private var store
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.listDensity, store: AppGroup.defaults) private var densityRaw = ListDensity.comfortable.rawValue

    @State private var path: [Int] = []
    @State private var searchText = ""
    @Namespace private var zoom

    private var density: ListDensity { ListDensity(rawValue: densityRaw) ?? .comfortable }

    var body: some View {
        @Bindable var store = store
        @Bindable var router = router
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                QuickFilterBar(selection: $store.filter, counts: store.counts)
                if store.isOffline, let lastSync = store.lastSync {
                    OfflineBanner(lastSync: lastSync)
                }
                listBody
            }
            .navigationTitle(title)
            .toolbar {
                if let tag = store.tagFilter {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation { store.tagFilter = nil }
                        } label: {
                            Label {
                                HStack(spacing: 4) {
                                    Text(tag)
                                    Image(systemName: "xmark").font(.caption2.weight(.semibold))
                                }
                            } icon: {
                                Image(systemName: "tag")
                            }
                        }
                        .accessibilityLabel(Text("Retirer le filtre \(tag)"))
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Rechercher"))
            .task(id: searchText) {
                try? await Task.sleep(for: .milliseconds(200))
                store.query = searchText
            }
            .navigationDestination(for: Int.self) { id in destination(id) }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    router.showAdd()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: Metrics.floatingButton, height: Metrics.floatingButton)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .padding(.trailing, 20)
                .padding(.bottom, 16)
                .accessibilityLabel(Text("Ajouter un favori"))
            }
            .sheet(item: $router.addRequest) { request in
                AddBookmarkSheet(prefillURL: request.url, prefillTitle: request.title)
            }
            .onChange(of: router.pendingBookmarkID) { _, id in
                guard let id else { return }
                path = [id]
                router.pendingBookmarkID = nil
            }
        }
    }

    private var title: Text {
        if let tag = store.tagFilter { return Text(tag) }
        return store.filter == .archived ? Text("Archivés") : Text("Favoris")
    }

    @ViewBuilder
    private var listBody: some View {
        let list = store.filtered
        if store.isLoading && store.bookmarks.isEmpty {
            LoadingPlaceholderList(density: density)
        } else if let error = store.loadError, store.bookmarks.isEmpty {
            ServerErrorView(error: error) { Task { await store.refresh() } }
        } else if store.hasLoadedOnce && store.counts.all == 0 && store.filter != .archived && store.tagFilter == nil && store.query.isEmpty {
            EmptyBookmarksView { router.showAdd() }
        } else if list.isEmpty && !store.query.isEmpty {
            NoResultsView(query: store.query) { searchText = "" }
        } else {
            BookmarkRows(bookmarks: list, density: density, zoom: zoom)
        }
    }

    @ViewBuilder
    private func destination(_ id: Int) -> some View {
        let detail = BookmarkDetailView(bookmarkID: id)
        if store.bookmark(id: id)?.hasPreviewImage == true {
            detail.navigationTransition(.zoom(sourceID: id, in: zoom))
        } else {
            detail
        }
    }
}

/// Plain list of rows with navigation, swipe actions and context menus.
struct BookmarkRows: View {
    let bookmarks: [Bookmark]
    let density: ListDensity
    let zoom: Namespace.ID
    @Environment(BookmarkStore.self) private var store

    var body: some View {
        List(bookmarks) { bookmark in
            NavigationLink(value: bookmark.id) {
                BookmarkRow(bookmark: bookmark, density: density)
            }
            .listRowInsets(EdgeInsets(top: density == .compact ? Metrics.cellPaddingCompact : Metrics.cellPadding,
                                      leading: Metrics.screenMargin,
                                      bottom: density == .compact ? Metrics.cellPaddingCompact : Metrics.cellPadding,
                                      trailing: Metrics.screenMargin))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .matchedTransitionSource(id: bookmark.id, in: zoom)
            .bookmarkSwipeActions(bookmark)
            .contextMenu {
                BookmarkMenuItems(bookmark: bookmark)
            } preview: {
                BookmarkPreview(bookmark: bookmark)
            }
        }
        .listStyle(.plain)
        .refreshable { await store.refresh() }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bookmarks.map(\.id))
    }
}

extension View {
    /// Trailing swipe: Read/Unread (accent), Archive (orange), Delete (red,
    /// full swipe). Each one is also exposed as an accessibility action.
    func bookmarkSwipeActions(_ bookmark: Bookmark) -> some View {
        modifier(BookmarkSwipeActions(bookmark: bookmark))
    }
}

private struct BookmarkSwipeActions: ViewModifier {
    let bookmark: Bookmark
    @Environment(BookmarkStore.self) private var store

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    store.delete(bookmark)
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
                Button {
                    store.setArchived(bookmark, !bookmark.isArchived)
                } label: {
                    Label(bookmark.isArchived ? "Désarchiver" : "Archiver", systemImage: "archivebox")
                }
                .tint(.orange)
                Button {
                    store.toggleUnread(bookmark)
                } label: {
                    Label(bookmark.unread ? "Lu" : "Non lu", systemImage: bookmark.unread ? "envelope.open" : "envelope.badge")
                }
                .tint(Color.accentColor)
            }
            .accessibilityAction(named: bookmark.unread ? Text("Marquer lu") : Text("Marquer non lu")) { store.toggleUnread(bookmark) }
            .accessibilityAction(named: bookmark.isArchived ? Text("Désarchiver") : Text("Archiver")) { store.setArchived(bookmark, !bookmark.isArchived) }
            .accessibilityAction(named: Text("Supprimer")) { store.delete(bookmark) }
    }
}
