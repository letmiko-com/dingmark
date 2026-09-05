import SwiftUI

/// Plain list of tags with counts. Tapping filters the bookmark list.
struct TagListScreen: View {
    @Environment(BookmarkStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var query = ""

    private var tags: [(name: String, count: Int)] {
        let all = store.tagCounts
        let q = TagNormalizer.normalize(query)
        return q.isEmpty ? all : all.filter { TagNormalizer.normalize($0.name).contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(tags, id: \.name) { tag in
                Button {
                    store.tagFilter = tag.name
                    store.filter = .all
                    router.tab = .bookmarks
                } label: {
                    HStack(spacing: 12) {
                        Label(tag.name, systemImage: "tag")
                        Spacer()
                        Text(tag.count, format: .number).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
            .listStyle(.plain)
            .navigationTitle("Tags")
            .searchable(text: $query, prompt: Text("Rechercher un tag"))
            .overlay {
                if tags.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView("Aucun tag", systemImage: "tag", description: Text("Les tags apparaissent avec les favoris qui les portent."))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
        }
    }
}
