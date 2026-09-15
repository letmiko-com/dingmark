import SwiftUI

/// [unread dot] favicon · title (semibold when unread, never truncated),
/// domain (+ globe when shared), description on two lines, tag chips · age.
struct BookmarkRow: View {
    let bookmark: Bookmark
    var density: ListDensity = .comfortable
    var selected = false

    @Environment(\.dynamicTypeSize) private var typeSize

    private var primary: Color { selected ? .white : .primary }
    private var secondary: Color { selected ? .white.opacity(0.75) : Color(.secondaryLabel) }
    private var tertiary: Color { selected ? .white.opacity(0.6) : Color(.tertiaryLabel) }
    private var showsDescription: Bool { density == .comfortable && !bookmark.displayDescription.isEmpty }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var standardLayout: some View {
        HStack(alignment: .top, spacing: Metrics.cellPadding) {
            unreadDot.padding(.top, 8).padding(.trailing, -6)
            FaviconView(bookmark: bookmark).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                titleText
                domainLine
                if showsDescription { descriptionText }
                tagsLine
            }
            Spacer(minLength: 0)
            Text(RelativeAge.string(from: bookmark.dateAdded))
                .font(.footnote)
                .foregroundStyle(tertiary)
                .padding(.top, 3)
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                unreadDot
                FaviconView(bookmark: bookmark, size: 34)
            }
            titleText
            domainLine
            Text(RelativeAge.string(from: bookmark.dateAdded)).font(.footnote).foregroundStyle(tertiary)
            if showsDescription { descriptionText }
            tagsLine
        }
    }

    @ViewBuilder
    private var unreadDot: some View {
        Circle()
            .fill(selected ? Color.white : Color.accentColor)
            .frame(width: Metrics.unreadDot, height: Metrics.unreadDot)
            .opacity(bookmark.unread ? 1 : 0)
            .scaleEffect(bookmark.unread ? 1 : 0.01)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: bookmark.unread)
    }

    private var titleText: some View {
        Text(bookmark.displayTitle)
            .font(.body.weight(bookmark.unread ? .semibold : .regular))
            .foregroundStyle(primary)
            .multilineTextAlignment(.leading)
    }

    private var domainLine: some View {
        HStack(spacing: 6) {
            Text(bookmark.domain).font(.footnote).foregroundStyle(secondary).lineLimit(1)
            if bookmark.shared {
                Image(systemName: "globe").font(.caption2).foregroundStyle(tertiary)
            }
        }
    }

    private var descriptionText: some View {
        Text(bookmark.displayDescription)
            .font(.subheadline)
            .foregroundStyle(secondary)
            .lineLimit(2)
    }

    @ViewBuilder
    private var tagsLine: some View {
        if bookmark.hasTags && density == .comfortable {
            FlowLayout(spacing: 6) {
                ForEach(bookmark.tagNames, id: \.self) { TagChip(name: $0, style: .cell) }
            }
            .padding(.top, 4)
        }
    }

    private var accessibilityText: Text {
        var parts: [String] = []
        if bookmark.unread { parts.append(String(localized: "Non lu")) }
        parts.append(bookmark.displayTitle)
        parts.append(bookmark.domain)
        if bookmark.hasTags { parts.append(bookmark.tagNames.joined(separator: ", ")) }
        parts.append(bookmark.dateAdded.formatted(.relative(presentation: .named)))
        return Text(parts.joined(separator: ", "))
    }
}

/// Content of the context menu preview: image when present, domain, title,
/// description.
struct BookmarkPreview: View {
    let bookmark: Bookmark

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = bookmark.previewImage {
                ServerImage(url: image) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(Color(.tertiarySystemFill))
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text(bookmark.domain).font(.subheadline).foregroundStyle(.secondary)
            Text(bookmark.displayTitle).font(.body.weight(.semibold))
            if !bookmark.displayDescription.isEmpty {
                Text(bookmark.displayDescription).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

/// Menu items shared by the context menu and the detail's ellipsis menu.
struct BookmarkMenuItems: View {
    let bookmark: Bookmark
    var afterDelete: () -> Void = {}

    @Environment(BookmarkStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            store.toggleUnread(bookmark)
        } label: {
            Label(bookmark.unread ? "Marquer lu" : "Marquer non lu", systemImage: bookmark.unread ? "envelope.open" : "envelope.badge")
        }
        if let url = bookmark.resolvedURL {
            Button {
                store.recordOpen(bookmark)
                openURL(url)
            } label: {
                Label("Ouvrir dans Safari", systemImage: "safari")
            }
            Button {
                UIPasteboard.general.url = url
                store.show(String(localized: "URL copiée"))
            } label: {
                Label("Copier l’URL", systemImage: "doc.on.doc")
            }
            ShareLink(item: url) {
                Label("Partager…", systemImage: "square.and.arrow.up")
            }
        }
        Button {
            store.setArchived(bookmark, !bookmark.isArchived)
        } label: {
            Label(bookmark.isArchived ? "Désarchiver" : "Archiver", systemImage: "archivebox")
        }
        Divider()
        Button(role: .destructive) {
            store.delete(bookmark)
            afterDelete()
        } label: {
            Label("Supprimer", systemImage: "trash")
        }
    }
}
