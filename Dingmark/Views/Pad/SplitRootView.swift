import SwiftUI

/// iPad: three columns, sidebar (filters + tags), list, detail. Same views as
/// the phone, only the container changes.
struct SplitRootView: View {
    @Environment(BookmarkStore.self) private var store
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.listDensity, store: AppGroup.defaults) private var densityRaw = ListDensity.comfortable.rawValue
    @AppStorage(SettingsKey.readingOrder, store: AppGroup.defaults) private var orderRaw = ReadingOrder.oldestFirst.rawValue

    @State private var columns: NavigationSplitViewVisibility = .all
    /// One element outside edit mode (drives the detail), any number inside.
    @State private var selection = Set<Int>()
    @State private var editMode: EditMode = .inactive
    @State private var showSettings = false
    @State private var searchText = ""
    /// The reading queue is a sidebar destination of its own, not a filter
    /// of the store: the library keeps its filter while it is shown.
    @State private var showsReadingQueue = false

    private enum SidebarItem: Hashable {
        case reading
        case filter(QuickFilter)
        case tag(String)
    }

    private var density: ListDensity { ListDensity(rawValue: densityRaw) ?? .comfortable }
    private var readingOrder: ReadingOrder { ReadingOrder(rawValue: orderRaw) ?? .oldestFirst }
    private var readingQueue: [Bookmark] { BookmarkFilter.readingList(store.bookmarks, order: readingOrder) }
    private var rows: [Bookmark] { showsReadingQueue ? readingQueue : store.filtered }
    private var selectedID: Int? { editMode.isEditing || selection.count != 1 ? nil : selection.first }

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding {
            if showsReadingQueue { return .reading }
            if let tag = store.tagFilter { return .tag(tag) }
            return .filter(store.filter)
        } set: { item in
            switch item {
            case .reading?:
                showsReadingQueue = true
            case .filter(let filter)?:
                showsReadingQueue = false
                store.filter = filter
                store.tagFilter = nil
            case .tag(let tag)?:
                showsReadingQueue = false
                store.tagFilter = tag
                store.filter = .all
            case nil:
                break
            }
        }
    }

    var body: some View {
        @Bindable var router = router
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: sidebarSelection) {
                Section {
                    Label("À lire", systemImage: "book")
                        .badge(store.counts.unread)
                        .tag(SidebarItem.reading)
                }
                Section {
                    ForEach(QuickFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.symbol)
                            .badge(store.counts.value(for: filter))
                            .tag(SidebarItem.filter(filter))
                    }
                }
                Section("Tags") {
                    ForEach(store.tagCounts, id: \.name) { tag in
                        Label(tag.name, systemImage: "tag")
                            .badge(tag.count)
                            .tag(SidebarItem.tag(tag.name))
                    }
                }
            }
            .navigationTitle("Dingmark")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        router.showAdd()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Ajouter un favori"))
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Réglages", systemImage: "gear")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } content: {
            List(rows, selection: $selection) { bookmark in
                BookmarkRow(bookmark: bookmark, density: density, selected: selectedID == bookmark.id,
                            highlight: showsReadingQueue ? [] : store.searchTerms)
                    .tag(bookmark.id)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(selectedID == bookmark.id ? Color.dingmarkAccent : Color.clear)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .bookmarkSwipeActions(bookmark)
                    .contextMenu {
                        BookmarkMenuItems(bookmark: bookmark) { selection.remove(bookmark.id) }
                    } preview: {
                        BookmarkPreview(bookmark: bookmark)
                    }
            }
            .listStyle(.plain)
            .navigationTitle(editMode.isEditing ? Text("\(selection.count) sélectionnés") : listTitle)
            .navigationBarTitleDisplayMode(.inline)
            .bulkSelection(selection: $selection, editMode: $editMode,
                           visibleIDs: rows.map(\.id), archivedContext: !showsReadingQueue && store.filter == .archived)
            .toolbar {
                if !editMode.isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        if showsReadingQueue {
                            ReadingOrderMenu(selection: $orderRaw)
                        } else {
                            SortMenu(selection: $store.sort)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: Text("Rechercher"))
            .task(id: searchText) {
                try? await Task.sleep(for: .milliseconds(200))
                store.query = searchText
            }
            .refreshable { await store.refresh() }
            .safeAreaInset(edge: .top) {
                if store.isOffline, let lastSync = store.lastSync {
                    OfflineBanner(lastSync: lastSync).padding(.top, 8)
                } else if let error = store.loadError, !store.bookmarks.isEmpty {
                    RefreshErrorBanner(error: error).padding(.top, 8)
                }
            }
            .overlay { contentOverlay }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            NavigationStack {
                if let id = selectedID, store.bookmark(id: id) != nil {
                    BookmarkDetailView(bookmarkID: id)
                } else {
                    ContentUnavailableView("Sélectionnez un favori", systemImage: "bookmark")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $router.addRequest) { request in
            AddBookmarkSheet(prefillURL: request.url, prefillTitle: request.title)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsForm()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("OK") { showSettings = false }
                        }
                    }
            }
        }
        .onChange(of: router.pendingBookmarkID) { _, _ in consumePendingBookmark() }
        .onChange(of: router.tab) { _, tab in
            // The phone's tabs map onto the sidebar here.
            if tab == .reading { showsReadingQueue = true }
        }
        .onAppear {
            consumePendingBookmark()
            if router.tab == .reading { showsReadingQueue = true }
        }
    }

    private func consumePendingBookmark() {
        guard let id = router.pendingBookmarkID else { return }
        showsReadingQueue = false
        editMode = .inactive
        selection = [id]
        router.pendingBookmarkID = nil
    }

    private var listTitle: Text {
        if showsReadingQueue { return Text("À lire") }
        if let tag = store.tagFilter { return Text(tag) }
        return store.filter == .archived ? Text("Archivés") : Text("Favoris")
    }

    @ViewBuilder
    private var contentOverlay: some View {
        if store.isLoading && store.bookmarks.isEmpty {
            LoadingPlaceholderList(density: density)
        } else if let error = store.loadError, store.bookmarks.isEmpty {
            ServerErrorView(error: error) { Task { await store.refresh() } }
        } else if showsReadingQueue {
            if readingQueue.isEmpty && store.hasLoadedOnce {
                FilteredEmptyView(filter: .unread, tag: nil)
            }
        } else if store.hasLoadedOnce && store.counts.all == 0 && store.filter != .archived && store.tagFilter == nil && store.query.isEmpty {
            EmptyBookmarksView { router.showAdd() }
        } else if store.filtered.isEmpty && !store.query.isEmpty {
            NoResultsView(query: store.query) { searchText = "" }
        } else if store.filtered.isEmpty && store.hasLoadedOnce {
            FilteredEmptyView(filter: store.filter, tag: store.tagFilter)
        }
    }
}
