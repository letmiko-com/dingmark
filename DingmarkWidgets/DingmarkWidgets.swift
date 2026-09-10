import WidgetKit
import SwiftUI

@main
struct DingmarkWidgetBundle: WidgetBundle {
    var body: some Widget {
        UnreadWidget()
    }
}

struct UnreadEntry: TimelineEntry {
    let date: Date
    let unread: [Bookmark]
    let configured: Bool
}

/// Reads the cache written by the app in the App Group container.
struct UnreadProvider: TimelineProvider {
    func placeholder(in context: Context) -> UnreadEntry {
        UnreadEntry(date: .now, unread: Self.unread(in: DemoData.bookmarks), configured: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (UnreadEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UnreadEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func load() -> UnreadEntry {
        let configured = AppGroup.defaults.string(forKey: SettingsKey.serverURL) != nil
        let snapshot = BookmarkCache.shared.load()
        return UnreadEntry(date: .now, unread: Self.unread(in: snapshot?.bookmarks ?? []), configured: configured || snapshot != nil)
    }

    static func unread(in bookmarks: [Bookmark]) -> [Bookmark] {
        bookmarks.filter { !$0.isArchived && $0.unread }.sorted { $0.dateAdded > $1.dateAdded }
    }
}

struct UnreadWidget: Widget {
    let kind = "app.letmiko.dingmark.unread"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UnreadProvider()) { entry in
            UnreadWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("Non lus"))
        .description(Text("Vos derniers favoris à lire et un bouton d’ajout rapide."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

enum DeepLink {
    static let add = URL(string: "dingmark://add")!
    static func bookmark(_ id: Int) -> URL { URL(string: "dingmark://bookmark/\(id)")! }
}

struct UnreadWidgetView: View {
    let entry: UnreadEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: SmallUnreadView(entry: entry)
        case .systemMedium: MediumUnreadView(entry: entry)
        case .accessoryCircular: CircularUnreadView(count: entry.unread.count)
        case .accessoryRectangular: RectangularUnreadView(entry: entry)
        default: SmallUnreadView(entry: entry)
        }
    }
}

/// Icon + counter, the latest unread bookmark on two lines, an add button.
/// The background opens the latest bookmark; Add has its own destination.
struct SmallUnreadView: View {
    let entry: UnreadEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                DingmarkGlyph(size: 20)
                Spacer()
                Text("\(entry.unread.count) non lus").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let first = entry.unread.first {
                VStack(alignment: .leading, spacing: 3) {
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                    Text(first.displayTitle).font(.footnote.weight(.semibold)).lineLimit(2)
                    Text(first.domain).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text(entry.configured ? "Aucun favori non lu" : "Ouvrez Dingmark pour vous connecter")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Link(destination: DeepLink.add) {
                Label("Ajouter", systemImage: "plus")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: Capsule())
            }
        }
        .widgetURL(entry.unread.first.map { DeepLink.bookmark($0.id) } ?? DeepLink.add)
    }
}

/// Header + three unread rows, right column with the mark and a round add
/// button.
struct MediumUnreadView: View {
    let entry: UnreadEntry

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Non lus").font(.footnote.weight(.semibold))
                    Spacer()
                    Text(entry.unread.count, format: .number).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)
                if entry.unread.isEmpty {
                    Text(entry.configured ? "Aucun favori non lu" : "Ouvrez Dingmark pour vous connecter")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(entry.unread.prefix(3)) { bookmark in
                        Link(destination: DeepLink.bookmark(bookmark.id)) {
                            HStack(spacing: 8) {
                                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                FaviconView(bookmark: bookmark, size: 20)
                                Text(bookmark.displayTitle).font(.footnote.weight(.medium)).lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            VStack {
                DingmarkGlyph(size: 22)
                Spacer()
                Link(destination: DeepLink.add) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.light))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Circle())
                }
                .accessibilityLabel(Text("Ajouter"))
            }
            .frame(width: 64, alignment: .trailing)
        }
    }
}

struct CircularUnreadView: View {
    let count: Int

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "bookmark.fill").font(.caption2)
                Text(count, format: .number).font(.headline)
            }
        }
        .widgetURL(DeepLink.add)
    }
}

struct RectangularUnreadView: View {
    let entry: UnreadEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DINGMARK · \(entry.unread.count) NON LUS")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            if let first = entry.unread.first {
                Text(first.displayTitle).font(.footnote.weight(.semibold)).lineLimit(1)
                Text(first.domain).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Aucun favori non lu").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .widgetURL(entry.unread.first.map { DeepLink.bookmark($0.id) } ?? DeepLink.add)
    }
}

#Preview(as: .systemSmall) {
    UnreadWidget()
} timeline: {
    UnreadEntry(date: .now, unread: UnreadProvider.unread(in: DemoData.bookmarks), configured: true)
}

#Preview(as: .systemMedium) {
    UnreadWidget()
} timeline: {
    UnreadEntry(date: .now, unread: UnreadProvider.unread(in: DemoData.bookmarks), configured: true)
}
