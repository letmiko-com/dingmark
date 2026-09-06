import Foundation

/// Compact age of a bookmark: "2 j", "1 sem.", "3 mois" (never "il y a").
enum RelativeAge {
    /// The unit picked for an age, before any translation. The thresholds live
    /// here so that they can be tested whatever the language of the runner:
    /// comparing the rendered string would fail on an English simulator.
    enum Unit: Equatable {
        case now
        case hours(Int)
        case days(Int)
        case weeks(Int)
        case months(Int)
        case years(Int)
    }

    static func unit(from date: Date, now: Date = .now) -> Unit {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 60 { return .now }
        let hours = minutes / 60
        if hours < 24 { return .hours(hours) }
        let days = hours / 24
        if days < 7 { return .days(days) }
        if days < 30 { return .weeks(days / 7) }
        if days < 365 { return .months(max(1, days / 30)) }
        return .years(days / 365)
    }

    static func string(from date: Date, now: Date = .now) -> String {
        switch unit(from: date, now: now) {
        case .now:
            return String(localized: "maint.", comment: "Bookmark age: just now")
        case .hours(let hours):
            return String(localized: "\(hours) h", comment: "Bookmark age in hours")
        case .days(let days):
            return String(localized: "\(days) j", comment: "Bookmark age in days")
        case .weeks(let weeks):
            return String(localized: "\(weeks) sem.", comment: "Bookmark age in weeks")
        case .months(let months):
            return String(localized: "\(months) mois", comment: "Bookmark age in months")
        case .years(let years):
            return String(localized: "\(years) an", comment: "Bookmark age in years")
        }
    }
}
