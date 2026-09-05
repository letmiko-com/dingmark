import Foundation

/// The fixtures of the design prototype: previews, redacted placeholders,
/// the `-demo` launch argument and the widget placeholder.
enum DemoData {
    static let host = "links.example.org"

    static let tags = ["selfhosting", "docker", "swift", "swiftui", "design", "réseau", "lecture", "recettes", "musique", "inbox", "ios", "sécurité"]

    static var bookmarks: [Bookmark] {
        let now = Date.now
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        return [
            Bookmark(id: 1, url: "https://tailscale.com/kb/1193/tailscale-ssh", title: "Tailscale SSH — Tailscale Docs",
                     description: "Use Tailscale to authenticate and authorize SSH connections on your tailnet, without managing keys.",
                     notes: "# À tester\n- Remplacer les clés sur le NAS\n- Vérifier les ACL avant de couper le port 22",
                     previewImageUrl: "https://picsum.photos/seed/tailscale/800/450", unread: true, tagNames: ["selfhosting", "réseau"], dateAdded: ago(2), dateModified: ago(2)),
            Bookmark(id: 2, url: "https://immich.app", title: "Immich — Self-hosted photo and video management",
                     description: "High performance self-hosted photo and video backup solution directly from your mobile phone.",
                     previewImageUrl: "https://picsum.photos/seed/immich/800/450", unread: true, shared: true, tagNames: ["selfhosting", "docker"], dateAdded: ago(3), dateModified: ago(3)),
            Bookmark(id: 3, url: "https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass", title: "Adopting Liquid Glass — Apple Developer",
                     description: "Find out how to bring the new material to your app.",
                     notes: "- Ne pas empiler du verre sur du verre\n- `glassEffect()` seulement sur les contrôles flottants",
                     tagNames: ["swiftui", "design"], dateAdded: ago(6), dateModified: ago(6)),
            Bookmark(id: 4, url: "https://www.marmiton.org/recettes/focaccia", title: "Focaccia maison, la recette de base",
                     description: "Une pâte très hydratée, une longue pousse au frais et beaucoup d’huile d’olive.",
                     previewImageUrl: "https://picsum.photos/seed/focaccia/800/450", unread: true, tagNames: ["recettes"], dateAdded: ago(8), dateModified: ago(8)),
            Bookmark(id: 5, url: "https://restic.net", title: "Restic — Backups done right",
                     description: "Fast, secure, efficient backup program.", tagNames: ["selfhosting", "sécurité"], dateAdded: ago(11), dateModified: ago(10)),
            Bookmark(id: 6, url: "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/", title: "The Swift Programming Language — Concurrency",
                     description: "Perform asynchronous operations.", tagNames: ["swift"], dateAdded: ago(16), dateModified: ago(16)),
            Bookmark(id: 7, url: "https://www.monde-diplomatique.fr/cartes", title: "Le Monde diplomatique — Cartographie",
                     description: "Les cartes du Monde diplomatique.", previewImageUrl: "https://picsum.photos/seed/cartes/800/450", unread: true, dateAdded: ago(18), dateModified: ago(18)),
            Bookmark(id: 8, url: "https://kiln.fm/loops", title: "Kiln — Mastering ambient guitar loops", tagNames: ["musique"], dateAdded: ago(24), dateModified: ago(24)),
            Bookmark(id: 9, url: "https://caddyserver.com", title: "Caddy — The Ultimate Server with Automatic HTTPS",
                     description: "Caddy is a powerful, enterprise-ready, open source web server with automatic HTTPS written in Go.",
                     isArchived: true, tagNames: ["selfhosting", "réseau", "docker"], dateAdded: ago(65), dateModified: ago(26)),
            Bookmark(id: 10, url: "https://internetactu.blog/lecture-lente", title: "Pourquoi la lecture lente",
                     description: "Reprendre le contrôle de son attention.", isArchived: true, tagNames: ["lecture"], dateAdded: ago(83), dateModified: ago(83)),
            Bookmark(id: 11, url: "https://docs.paperless-ngx.com", title: "Paperless-ngx documentation",
                     description: "Scan, index and archive all your physical documents.", shared: true, dateAdded: ago(94), dateModified: ago(94)),
        ]
    }

    /// Six rows for the redacted loading placeholder.
    static var placeholders: [Bookmark] { Array(bookmarks.prefix(6)) }
}
