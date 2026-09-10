import SwiftUI

/// The site favicon served by linkding, or the first letter of the domain on a
/// colour derived from the domain when there is none (or it fails to load).
struct FaviconView: View {
    let bookmark: Bookmark
    var size: CGFloat = Metrics.faviconSize

    var body: some View {
        Group {
            if let url = bookmark.favicon {
                ServerImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(size * 0.12).background(Color(.systemBackground))
                    } else {
                        letterTile
                    }
                }
            } else {
                letterTile
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 4, style: .continuous))
        .accessibilityHidden(true)
    }

    private var letterTile: some View {
        ZStack {
            DomainColor.color(for: bookmark.domain)
            Text(DomainColor.letter(for: bookmark.domain))
                .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

enum DomainColor {
    /// Palette of the design prototype.
    static let palette: [Color] = [
        Color(red: 0.14, green: 0.14, blue: 0.14),
        Color(red: 0.26, green: 0.31, blue: 0.69),
        Color(red: 0.91, green: 0.35, blue: 0.05),
        Color(red: 0.04, green: 0.45, blue: 0.52),
        Color(red: 0.94, green: 0.32, blue: 0.22),
        Color(red: 0.55, green: 0.12, blue: 0.12),
        Color(red: 0.36, green: 0.29, blue: 0.54),
        Color(red: 0.12, green: 0.62, blue: 0.33),
        Color(red: 0.23, green: 0.23, blue: 0.24),
        Color(red: 0.09, green: 0.33, blue: 0.12),
    ]

    static func color(for domain: String) -> Color {
        palette[Int(stableHash(domain) % UInt64(palette.count))]
    }

    static func letter(for domain: String) -> String {
        domain.first.map { String($0).uppercased() } ?? "?"
    }

    /// FNV-1a: `hashValue` is randomised per launch, colours must not be.
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        return h
    }
}
