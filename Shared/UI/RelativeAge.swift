import Foundation

/// Compact age of a bookmark: "2 j", "1 sem.", "3 mois" (never "il y a").
enum RelativeAge {
    static func string(from date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 60 { return String(localized: "maint.", comment: "Bookmark age: just now") }
        let hours = minutes / 60
        if hours < 24 { return String(localized: "\(hours) h", comment: "Bookmark age in hours") }
        let days = hours / 24
        if days < 7 { return String(localized: "\(days) j", comment: "Bookmark age in days") }
        if days < 30 { return String(localized: "\(days / 7) sem.", comment: "Bookmark age in weeks") }
        if days < 365 { return String(localized: "\(max(1, days / 30)) mois", comment: "Bookmark age in months") }
        return String(localized: "\(days / 365) an", comment: "Bookmark age in years")
    }
}
