import SwiftUI
import UIKit

extension Color {
    /// Brand fill of the design: rgb(0,199,190) in light, rgb(0,210,224) in
    /// dark (the system teal/mint family). Also declared as `AccentColor` in
    /// the asset catalogs so system chrome picks it up. Too light to carry
    /// white text or to be text on white (2.1:1): text on it is `onAccent`,
    /// tinted text uses `dingmarkTint`.
    static let dingmarkAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0, green: 210 / 255, blue: 224 / 255, alpha: 1)
            : UIColor(red: 0, green: 199 / 255, blue: 190 / 255, alpha: 1)
    })

    /// Tint of text and controls on the system background: the same teal
    /// darkened in light mode to reach 4.7:1 on white (WCAG AA), the brand
    /// teal in dark mode where it already reads at 11:1 on black.
    static let dingmarkTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0, green: 210 / 255, blue: 224 / 255, alpha: 1)
            : UIColor(red: 0, green: 130 / 255, blue: 124 / 255, alpha: 1)
    })

    /// Text and symbols placed on a `dingmarkAccent` fill: black in both
    /// modes (9.9:1 in light, 11:1 in dark), where white would give 2.1:1.
    static let onAccent = Color.black
}

extension View {
    /// A prominent button in the brand teal with black content: the fill
    /// keeps the design's colour, the text stays readable.
    func accentProminent() -> some View {
        tint(.dingmarkAccent).foregroundStyle(Color.onAccent)
    }
}

/// Spacing and radii of the spec, in points.
enum Metrics {
    static let screenMargin: CGFloat = 16
    static let cellPadding: CGFloat = 12
    static let cellPaddingCompact: CGFloat = 9
    static let faviconSize: CGFloat = 28
    static let faviconRadius: CGFloat = 7
    static let unreadDot: CGFloat = 8
    static let groupRadius: CGFloat = 26
    static let filterHeight: CGFloat = 32
    static let buttonHeight: CGFloat = 50
    static let floatingButton: CGFloat = 48
    /// Banner distance from the bottom edge: above the floating tab bar on
    /// the phone, a plain margin on the iPad.
    static let toastBottomInset: CGFloat = 96
    static let toastBottomInsetRegular: CGFloat = 24
}
