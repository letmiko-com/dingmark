import Testing
import Foundation
@testable import Dingmark

@Suite("LinkdingDate")
struct LinkdingDateTests {
    @Test("six fractional digits, as emitted by Django REST framework")
    func parsesMicroseconds() throws {
        let date = try #require(LinkdingDate.parse("2020-09-26T09:46:23.006313Z"))
        let comps = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        #expect(comps.year == 2020 && comps.month == 9 && comps.day == 26)
        #expect(comps.hour == 9 && comps.minute == 46 && comps.second == 23)
    }

    @Test("no fraction")
    func parsesPlain() throws {
        let date = try #require(LinkdingDate.parse("2025-01-01T00:00:00Z"))
        #expect(date.timeIntervalSince1970 == 1_735_689_600)
    }

    @Test("one fractional digit and a numeric offset")
    func parsesShortFractionWithOffset() throws {
        let date = try #require(LinkdingDate.parse("2025-01-01T01:00:00.5+01:00"))
        #expect(abs(date.timeIntervalSince1970 - 1_735_689_600.5) < 0.001)
    }

    @Test("garbage is nil, not a crash")
    func rejectsGarbage() {
        #expect(LinkdingDate.parse("hier") == nil)
        #expect(LinkdingDate.parse("") == nil)
    }
}
