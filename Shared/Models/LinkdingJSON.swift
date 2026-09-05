import Foundation

/// JSON coding configured for the linkding API.
enum LinkdingJSON {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = LinkdingDate.parse(raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unreadable date \(raw)"))
            }
            return date
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

/// linkding (Django REST framework) emits ISO 8601 with six fractional digits
/// (`2020-09-26T09:46:23.006313Z`) or none. `ISO8601DateFormatter` only
/// accepts exactly three, so the fraction is normalised first.
enum LinkdingDate {
    static func parse(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let dot = s.firstIndex(of: ".") else {
            return plain.date(from: s)
        }
        let afterDot = s[s.index(after: dot)...]
        let digits = afterDot.prefix { $0.isNumber }
        let rest = afterDot.dropFirst(digits.count)
        let fraction = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        let normalized = String(s[..<dot]) + "." + fraction + rest
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: normalized) ?? plain.date(from: String(s[..<dot]) + rest)
    }
}
