import SwiftUI

extension AttributedString {
    /// The text with every occurrence of the search terms marked (case and
    /// diacritic insensitive, like the search itself): the reader sees why
    /// a row matched.
    static func highlighting(_ text: String, terms: [String], color: Color = .dingmarkAccent) -> AttributedString {
        var result = AttributedString(text)
        guard !terms.isEmpty else { return result }
        for term in terms where !term.isEmpty {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: term, options: BookmarkFilter.searchOptions, range: searchRange) {
                if let lower = AttributedString.Index(found.lowerBound, within: result),
                   let upper = AttributedString.Index(found.upperBound, within: result) {
                    result[lower..<upper].backgroundColor = color.opacity(0.28)
                }
                guard found.upperBound < text.endIndex else { break }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return result
    }
}
