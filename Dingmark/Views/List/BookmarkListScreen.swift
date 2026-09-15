import SwiftUI

/// Main screen: large title, search drawer, quick filters, plain list with
/// swipe actions and context menu previews, floating add button.
struct BookmarkListScreen: View {
    @Environment(BookmarkStore.self) private var store
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.listDensity, store: AppGroup.defaults) private var densityRaw = ListDensity.comfortable.rawValue

    @State private var path: [Int] = []
    @State private var searchText = ""
    @State private var selection = Set<Int>()
    @State private var editMode: EditMode = .inactive
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
                } else if let error = store.loadError, !store.bookmarks.isEmpty {
                    RefreshErrorBanner(error: error)
                }
                listBody
            }
            .navigationTitle(editMode.isEditing ? Text("\(selection.count) sélectionnés") : title)
            .bulkSelection(selection: $selection, editMode: $editMode,
                           visibleIDs: store.filtered.map(\.id), archivedContext: store.filter == .archived)
            .toolbar {
                if !editMode.isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        SortMenu(selection: $store.sort)
                    }
                }
                if let tag = store.tagFilter, !editMode.isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation { store.tagFilter = nil }
                        } label: {
                            // Not a `Label`: the toolbar would keep only its
                            // icon, and the chip must read "tag name ×".
                            HStack(spacing: 5) {
                                Image(systemName: "tag")
                                Text(tag).lineLimit(1)
                                Image(systemName: "xmark").font(.caption2.weight(.semibold))
                            }
                            .padding(.horizontal, 4)
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
                if !editMode.isEditing {
                    Button {
                        router.showAdd()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .frame(width: Metrics.floatingButton, height: Metrics.floatingButton)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .accentProminent()
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
                    .accessibilityLabel(Text("Ajouter un favori"))
                }
            }
            .sheet(item: $router.addRequest) { request in
                AddBookmarkSheet(prefillURL: request.url, prefillTitle: request.title)
            }
            .onChange(of: router.pendingBookmarkID) { _, _ in consumePendingBookmark() }
            .onAppear { consumePendingBookmark() }
        }
    }

    /// `dingmark://bookmark/<id>` can arrive before this screen exists (cold
    /// launch from a widget): consume it on appear as well as on change.
    private func consumePendingBookmark() {
        guard let id = router.pendingBookmarkID else { return }
        path = [id]
        router.pendingBookmarkID = nil
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
        } else if list.isEmpty && store.hasLoadedOnce {
            FilteredEmptyView(filter: store.filter, tag: store.tagFilter)
        } else {
            BookmarkRows(bookmarks: list, density: density, zoom: zoom, selection: $selection, highlight: store.searchTerms)
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

/// Plain list of rows with navigation, swipe actions and context menus. The
/// selection is bound in edit mode only: bound all the time, a tap on the
/// phone selects the row (iOS 26) instead of following the navigation link.
struct BookmarkRows: View {
    let bookmarks: [Bookmark]
    let density: ListDensity
    let zoom: Namespace.ID
    @Binding var selection: Set<Int>
    var highlight: [String] = []
    @Environment(BookmarkStore.self) private var store
    @Environment(\.editMode) private var editMode

    var body: some View {
        List(bookmarks, selection: editMode?.wrappedValue.isEditing == true ? $selection : nil) { bookmark in
            NavigationLink(value: bookmark.id) {
                BookmarkRow(bookmark: bookmark, density: density, highlight: highlight)
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
    /// Row swipes as configured in the settings: one action on the right
    /// (full swipe), the chosen action then the others on the left. Every
    /// action is also exposed as an accessibility action. `details` adds a
    /// Details button on the right where a tap does not open the detail.
    func bookmarkSwipeActions(_ bookmark: Bookmark, details: (() -> Void)? = nil) -> some View {
        modifier(BookmarkSwipeActions(bookmark: bookmark, details: details))
    }
}

private struct BookmarkSwipeActions: ViewModifier {
    let bookmark: Bookmark
    var details: (() -> Void)?
    @Environment(BookmarkStore.self) private var store
    @AppStorage(SettingsKey.swipeLeading, store: AppGroup.defaults) private var leadingRaw = SwipeConfiguration.default.leading.rawValue
    @AppStorage(SettingsKey.swipeTrailing, store: AppGroup.defaults) private var trailingRaw = SwipeConfiguration.default.trailing.rawValue

    private var configuration: SwipeConfiguration {
        SwipeConfiguration(leading: SwipeAction(rawValue: leadingRaw) ?? SwipeConfiguration.default.leading,
                           trailing: SwipeAction(rawValue: trailingRaw) ?? SwipeConfiguration.default.trailing)
    }

    func body(content: Content) -> some View {
        let configuration = configuration
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                ForEach(configuration.leadingActions) { button(for: $0) }
                if let details {
                    Button(action: details) {
                        Label("Détails", systemImage: "info.circle")
                    }
                    .tint(.indigo)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                ForEach(configuration.trailingActions) { button(for: $0) }
            }
            .accessibilityAction(named: bookmark.unread ? Text("Marquer lu") : Text("Marquer non lu")) { store.toggleUnread(bookmark) }
            .accessibilityAction(named: bookmark.isArchived ? Text("Désarchiver") : Text("Archiver")) { store.setArchived(bookmark, !bookmark.isArchived) }
            .accessibilityAction(named: Text("Supprimer")) { store.delete(bookmark) }
    }

    @ViewBuilder
    private func button(for action: SwipeAction) -> some View {
        switch action {
        case .toggleRead:
            Button {
                store.toggleUnread(bookmark)
            } label: {
                Label(bookmark.unread ? "Lu" : "Non lu", systemImage: bookmark.unread ? "envelope.open" : "envelope.badge")
            }
            .tint(Color.accentColor)
        case .archive:
            Button {
                store.setArchived(bookmark, !bookmark.isArchived)
            } label: {
                Label(bookmark.isArchived ? "Désarchiver" : "Archiver", systemImage: "archivebox")
            }
            .tint(.orange)
        case .delete:
            Button(role: .destructive) {
                store.delete(bookmark)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        case .none:
            EmptyView()
        }
    }
}
