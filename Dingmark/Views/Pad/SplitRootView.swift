import SwiftUI

/// iPad: three columns, sidebar (filters + tags), list, detail. Same views as
/// the phone, only the container changes.
struct SplitRootView: View {
    @Environment(BookmarkStore.self) private var store
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.listDensity, store: AppGroup.defaults) private var densityRaw = ListDensity.comfortable.rawValue

    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var selectedID: Int?
    @State private var showSettings = false
    @State private var searchText = ""

    private enum SidebarItem: Hashable {
        case filter(QuickFilter)
        case tag(String)
    }

    private var density: ListDensity { ListDensity(rawValue: densityRaw) ?? .comfortable }

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding {
            if let tag = store.tagFilter { return .tag(tag) }
            return .filter(store.filter)
        } set: { item in
            switch item {
            case .filter(let filter)?:
                store.filter = filter
                store.tagFilter = nil
            case .tag(let tag)?:
                store.tagFilter = tag
                store.filter = .all
            case nil:
                break
            }
        }
    }

    var body: some View {
        @Bindable var router = router
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: sidebarSelection) {
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
            List(store.filtered, selection: $selectedID) { bookmark in
                BookmarkRow(bookmark: bookmark, density: density, selected: selectedID == bookmark.id)
                    .tag(bookmark.id)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(selectedID == bookmark.id ? Color.accentColor : Color.clear)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .bookmarkSwipeActions(bookmark)
                    .contextMenu {
                        BookmarkMenuItems(bookmark: bookmark) { if selectedID == bookmark.id { selectedID = nil } }
                    } preview: {
                        BookmarkPreview(bookmark: bookmark)
                    }
            }
            .listStyle(.plain)
            .navigationTitle(listTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: Text("Rechercher"))
            .task(id: searchText) {
                try? await Task.sleep(for: .milliseconds(200))
                store.query = searchText
            }
            .refreshable { await store.refresh() }
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
        .onAppear { consumePendingBookmark() }
    }

    private func consumePendingBookmark() {
        guard let id = router.pendingBookmarkID else { return }
        selectedID = id
        router.pendingBookmarkID = nil
    }

    private var listTitle: Text {
        if let tag = store.tagFilter { return Text(tag) }
        return store.filter == .archived ? Text("Archivés") : Text("Favoris")
    }

    @ViewBuilder
    private var contentOverlay: some View {
        if store.isLoading && store.bookmarks.isEmpty {
            LoadingPlaceholderList(density: density)
        } else if let error = store.loadError, store.bookmarks.isEmpty {
            ServerErrorView(error: error) { Task { await store.refresh() } }
        } else if store.hasLoadedOnce && store.counts.all == 0 && store.filter != .archived && store.tagFilter == nil && store.query.isEmpty {
            EmptyBookmarksView { router.showAdd() }
        } else if store.filtered.isEmpty && !store.query.isEmpty {
            NoResultsView(query: store.query) { searchText = "" }
        } else if store.filtered.isEmpty && store.hasLoadedOnce {
            FilteredEmptyView(filter: store.filter, tag: store.tagFilter)
        }
    }
}
