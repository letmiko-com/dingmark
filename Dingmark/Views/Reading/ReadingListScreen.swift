import SwiftUI

extension ReadingOrder {
    var title: LocalizedStringKey {
        switch self {
        case .oldestFirst: "Plus anciens d’abord"
        case .newestFirst: "Plus récents d’abord"
        }
    }
}

/// The reading queue: unread active bookmarks, oldest first by default.
/// Tapping a row opens the page (Reader when available) and marks it read,
/// the banner then offers to archive. The detail stays one swipe away.
struct ReadingListScreen: View {
    @Environment(BookmarkStore.self) private var store
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKey.listDensity, store: AppGroup.defaults) private var densityRaw = ListDensity.comfortable.rawValue
    @AppStorage(SettingsKey.readingOrder, store: AppGroup.defaults) private var orderRaw = ReadingOrder.oldestFirst.rawValue
    @AppStorage(SettingsKey.openLinksInApp, store: AppGroup.defaults) private var openInApp = true
    @AppStorage(SettingsKey.readerMode, store: AppGroup.defaults) private var readerMode = true

    @State private var path: [Int] = []
    @State private var reading: Bookmark?
    @State private var lastRead: Bookmark?

    private var density: ListDensity { ListDensity(rawValue: densityRaw) ?? .comfortable }
    private var order: ReadingOrder { ReadingOrder(rawValue: orderRaw) ?? .oldestFirst }
    private var queue: [Bookmark] { BookmarkFilter.readingList(store.bookmarks, order: order) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.isLoading && store.bookmarks.isEmpty {
                    LoadingPlaceholderList(density: density)
                } else if queue.isEmpty {
                    ContentUnavailableView {
                        Label("Rien à lire", systemImage: "book")
                    } description: {
                        Text("Les favoris marqués non lus apparaissent ici.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("À lire")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ReadingOrderMenu(selection: $orderRaw)
                }
            }
            .navigationDestination(for: Int.self) { id in BookmarkDetailView(bookmarkID: id) }
            .fullScreenCover(item: $reading, onDismiss: finishReading) { bookmark in
                if let url = bookmark.resolvedURL {
                    SafariView(url: url, entersReader: readerMode) { reading = nil }
                        .ignoresSafeArea()
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(queue) { bookmark in
                    Button {
                        read(bookmark)
                    } label: {
                        BookmarkRow(bookmark: bookmark, density: density)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: density == .compact ? Metrics.cellPaddingCompact : Metrics.cellPadding,
                                              leading: Metrics.screenMargin,
                                              bottom: density == .compact ? Metrics.cellPaddingCompact : Metrics.cellPadding,
                                              trailing: Metrics.screenMargin))
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .bookmarkSwipeActions(bookmark) { path = [bookmark.id] }
                    .contextMenu {
                        Button {
                            path = [bookmark.id]
                        } label: {
                            Label("Détails", systemImage: "info.circle")
                        }
                        BookmarkMenuItems(bookmark: bookmark)
                    } preview: {
                        BookmarkPreview(bookmark: bookmark)
                    }
                    .accessibilityAction(named: Text("Détails")) { path = [bookmark.id] }
                }
            } header: {
                ReadingQueueHeader(queue: queue)
            }
        }
        .listStyle(.plain)
        .refreshable { await store.refresh() }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: queue.map(\.id))
    }

    private func read(_ bookmark: Bookmark) {
        guard let url = bookmark.resolvedURL else { return }
        lastRead = bookmark
        store.recordOpen(bookmark)
        if openInApp, url.scheme == "https" || url.scheme == "http" {
            reading = bookmark
        } else {
            openURL(url)
            finishReading()
        }
    }

    private func finishReading() {
        guard let bookmark = lastRead else { return }
        lastRead = nil
        store.finishReading(bookmark)
    }
}

/// Count and age of the oldest item, as a section header footnote.
struct ReadingQueueHeader: View {
    let queue: [Bookmark]

    var body: some View {
        if let oldest = queue.map(\.dateAdded).min() {
            Text("\(queue.count) à lire · le plus ancien attend depuis \(RelativeAge.string(from: oldest))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(nil)
                .padding(.horizontal, Metrics.screenMargin)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets())
        }
    }
}

extension BookmarkSort {
    var title: LocalizedStringKey {
        switch self {
        case .newestAdded: "Plus récents d’abord"
        case .oldestAdded: "Plus anciens d’abord"
        case .recentlyModified: "Modifiés récemment"
        case .title: "Titre"
        case .domain: "Domaine"
        }
    }
}

/// Order of the library list, one memory per filter.
struct SortMenu: View {
    @Binding var selection: BookmarkSort

    var body: some View {
        Menu {
            Picker("Trier", selection: $selection) {
                ForEach(BookmarkSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel(Text("Trier"))
    }
}

/// Oldest or newest first, remembered across launches.
struct ReadingOrderMenu: View {
    @Binding var selection: String

    var body: some View {
        Menu {
            Picker("Ordre de lecture", selection: $selection) {
                ForEach(ReadingOrder.allCases) { order in
                    Text(order.title).tag(order.rawValue)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel(Text("Ordre de lecture"))
    }
}
