import SwiftUI
import UIKit

extension Color {
    /// Accent of the design: rgb(0,199,190) in light, rgb(0,210,224) in dark
    /// (the system teal/mint family). Also declared as `AccentColor` in the
    /// asset catalogs so system chrome picks it up.
    static let dingmarkAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0, green: 210 / 255, blue: 224 / 255, alpha: 1)
            : UIColor(red: 0, green: 199 / 255, blue: 190 / 255, alpha: 1)
    })
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
