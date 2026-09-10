import Foundation

/// A linkding bookmark as returned by `GET /api/bookmarks/`.
///
/// Decoded with `LinkdingJSON.decoder` (snake_case keys, ISO 8601 dates with
/// a variable number of fractional digits). Optional fields of the API are
/// defaulted so an older linkding stays decodable.
struct Bookmark: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var url: String
    var title: String
    var description: String
    var notes: String
    var websiteTitle: String?
    var websiteDescription: String?
    var webArchiveSnapshotUrl: String?
    var faviconUrl: String?
    var previewImageUrl: String?
    var isArchived: Bool
    var unread: Bool
    var shared: Bool
    var tagNames: [String]
    var dateAdded: Date
    var dateModified: Date

    init(id: Int, url: String, title: String = "", description: String = "", notes: String = "",
         websiteTitle: String? = nil, websiteDescription: String? = nil,
         webArchiveSnapshotUrl: String? = nil, faviconUrl: String? = nil, previewImageUrl: String? = nil,
         isArchived: Bool = false, unread: Bool = false, shared: Bool = false, tagNames: [String] = [],
         dateAdded: Date = .now, dateModified: Date = .now) {
        self.id = id
        self.url = url
        self.title = title
        self.description = description
        self.notes = notes
        self.websiteTitle = websiteTitle
        self.websiteDescription = websiteDescription
        self.webArchiveSnapshotUrl = webArchiveSnapshotUrl
        self.faviconUrl = faviconUrl
        self.previewImageUrl = previewImageUrl
        self.isArchived = isArchived
        self.unread = unread
        self.shared = shared
        self.tagNames = tagNames
        self.dateAdded = dateAdded
        self.dateModified = dateModified
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        websiteTitle = try c.decodeIfPresent(String.self, forKey: .websiteTitle)
        websiteDescription = try c.decodeIfPresent(String.self, forKey: .websiteDescription)
        webArchiveSnapshotUrl = try c.decodeIfPresent(String.self, forKey: .webArchiveSnapshotUrl)
        faviconUrl = try c.decodeIfPresent(String.self, forKey: .faviconUrl)
        previewImageUrl = try c.decodeIfPresent(String.self, forKey: .previewImageUrl)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        unread = try c.decodeIfPresent(Bool.self, forKey: .unread) ?? false
        shared = try c.decodeIfPresent(Bool.self, forKey: .shared) ?? false
        tagNames = try c.decodeIfPresent([String].self, forKey: .tagNames) ?? []
        dateAdded = try c.decodeIfPresent(Date.self, forKey: .dateAdded) ?? .now
        dateModified = try c.decodeIfPresent(Date.self, forKey: .dateModified) ?? dateAdded
    }
}

extension Bookmark {
    /// Title to show: the user's title, else the scraped one, else the URL.
    var displayTitle: String {
        if !title.isEmpty { return title }
        if let websiteTitle, !websiteTitle.isEmpty { return websiteTitle }
        return url
    }

    var displayDescription: String {
        if !description.isEmpty { return description }
        return websiteDescription ?? ""
    }

    var domain: String { URLDomain.domain(of: url) }
    var resolvedURL: URL? { URL(string: url) }
    var hasPreviewImage: Bool { !(previewImageUrl ?? "").isEmpty }
    var previewImage: URL? { previewImageUrl.flatMap(URL.init(string:)) }
    var favicon: URL? { faviconUrl.flatMap(URL.init(string:)) }
    var hasTags: Bool { !tagNames.isEmpty }
    var hasNotes: Bool { !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Body of `POST /api/bookmarks/`.
struct BookmarkDraft: Codable, Hashable, Sendable {
    var url: String
    var title: String = ""
    var description: String = ""
    var notes: String = ""
    var isArchived: Bool = false
    var unread: Bool = false
    var shared: Bool = false
    var tagNames: [String] = []

    // POST can become an update when another client creates this URL between
    // our check and our save. Omit empty/default fields that need not erase it.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        if !title.isEmpty { try container.encode(title, forKey: .title) }
        if !description.isEmpty { try container.encode(description, forKey: .description) }
        if !notes.isEmpty { try container.encode(notes, forKey: .notes) }
        if isArchived { try container.encode(true, forKey: .isArchived) }
        try container.encode(unread, forKey: .unread)
        if shared { try container.encode(true, forKey: .shared) }
        if !tagNames.isEmpty { try container.encode(tagNames, forKey: .tagNames) }
    }
}

/// Body of `PATCH /api/bookmarks/<id>/`: only the provided fields change.
struct BookmarkPatch: Codable, Hashable, Sendable {
    var url: String? = nil
    var title: String? = nil
    var description: String? = nil
    var notes: String? = nil
    var isArchived: Bool? = nil
    var unread: Bool? = nil
    var shared: Bool? = nil
    var tagNames: [String]? = nil
}

/// Paginated list envelope of the linkding API.
struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
    var count: Int
    var next: String?
    var previous: String?
    var results: [Item]
}

/// `GET /api/bookmarks/check/?url=` response.
struct CheckResponse: Decodable, Sendable {
    struct Metadata: Decodable, Sendable {
        var title: String?
        var description: String?
        var previewImage: String?
    }
    var bookmark: Bookmark?
    var metadata: Metadata?
    var autoTags: [String]?
}

struct TagDTO: Decodable, Sendable {
    var id: Int
    var name: String
    var dateAdded: Date?
}
