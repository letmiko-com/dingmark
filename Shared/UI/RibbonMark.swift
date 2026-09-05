import SwiftUI

/// The "Ruban" mark of the app icon, drawn from the same 1024 grid as the
/// SVG sources in `design/icon/` so no bitmap is needed in the UI.
struct RibbonBandShape: Shape {
    func path(in rect: CGRect) -> Path {
        RibbonGeometry.path([(336, 150), (556, 150), (556, 790), (446, 700), (336, 790)], in: rect)
    }
}

struct RibbonFoldShape: Shape {
    func path(in rect: CGRect) -> Path {
        RibbonGeometry.path([(556, 150), (756, 350), (756, 600), (556, 400)], in: rect)
    }
}

enum RibbonGeometry {
    static let teal = Color(red: 0, green: 199 / 255, blue: 190 / 255)
    static let deepTeal = Color(red: 0, green: 127 / 255, blue: 122 / 255)
    static let darkGround = Color(red: 10 / 255, green: 46 / 255, blue: 44 / 255)

    static func path(_ points: [(CGFloat, CGFloat)], in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width, rect.height) / 1024
        let origin = CGPoint(x: rect.midX - 512 * scale, y: rect.midY - 512 * scale)
        for (i, p) in points.enumerated() {
            let point = CGPoint(x: origin.x + p.0 * scale, y: origin.y + p.1 * scale)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// The full app icon (ground + mark), squircle clipped. Used at 84 pt on the
/// login screen and 24 pt in the share extension header.
struct DingmarkIcon: View {
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 19 / 84, style: .continuous)
                .fill(scheme == .dark ? RibbonGeometry.darkGround : RibbonGeometry.teal)
            RibbonFoldShape().fill(RibbonGeometry.deepTeal)
            RibbonBandShape().fill(scheme == .dark ? RibbonGeometry.teal : Color.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The mark alone at 72 %, for widgets and places where the ground is given.
struct DingmarkGlyph: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RibbonFoldShape().fill(RibbonGeometry.deepTeal)
            RibbonBandShape().fill(RibbonGeometry.teal)
        }
        .frame(width: size * 0.72, height: size * 0.72)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
