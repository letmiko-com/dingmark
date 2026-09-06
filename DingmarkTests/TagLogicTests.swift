import Testing
import Foundation
@testable import Dingmark

@Suite("Tags")
struct TagLogicTests {
    @Test("normalisation: lowercase, no hash, no spaces")
    func normalize() {
        #expect(TagNormalizer.normalize(" #SelfHosting ") == "selfhosting")
        #expect(TagNormalizer.normalize("home lab") == "home-lab")
    }

    @Test("default tags: comma or space separated, deduplicated")
    func parseList() {
        #expect(TagList.parse("inbox, Inbox docker,,") == ["inbox", "docker"])
        #expect(TagList.join(["a", "b"]) == "a,b")
    }

    @Test("suggestions: existing matches, plus a creatable token when nothing matches exactly")
    func suggestions() {
        let pool = ["swift", "swiftui", "docker", "design"]
        let typed = TagSuggestions.compute(input: "sw", pool: pool, selected: [])
        #expect(typed.matches == ["swift", "swiftui"])
        #expect(typed.creatable == "sw")

        let exact = TagSuggestions.compute(input: "swift", pool: pool, selected: [])
        #expect(exact.creatable == nil)
        #expect(exact.matches.first == "swift")

        let taken = TagSuggestions.compute(input: "", pool: pool, selected: ["docker"])
        #expect(!taken.matches.contains("docker"))
        #expect(taken.creatable == nil)
    }

    @Test("pool: usage order first, then the other known tags, no duplicates")
    func pool() {
        let pool = TagSuggestions.pool(usage: [(name: "b", count: 3), (name: "a", count: 1)], known: ["a", "c", "b"])
        #expect(pool == ["b", "a", "c"])
    }
}

@Suite("URLDomain")
struct URLDomainTests {
    @Test("domain without www, tolerant to missing scheme")
    func domain() {
        #expect(URLDomain.domain(of: "https://www.marmiton.org/recettes/focaccia") == "marmiton.org")
        #expect(URLDomain.domain(of: "developer.apple.com/documentation") == "developer.apple.com")
        #expect(URLDomain.domain(of: "not a url") == "not a url")
    }

    @Test("first URL in pasted text, bare hosts and non-web links excluded")
    func firstURL() {
        #expect(URLDomain.firstURL(in: "voir https://immich.app/docs?x=1 et rien d’autre") == "https://immich.app/docs?x=1")
        #expect(URLDomain.firstURL(in: "https://a.example\nhttps://b.example") == "https://a.example")
        #expect(URLDomain.firstURL(in: "mailto:me@example.org") == nil)
        // Typed without a scheme: returned as typed, the caller defaults to https.
        #expect(URLDomain.firstURL(in: "links.example.org/x") == "links.example.org/x")
        #expect(URLDomain.firstURL(in: "pas de lien") == nil)
    }

    @Test("server normalisation keeps the origin and a mount prefix, drops linkding pages")
    func normalizeServer() {
        #expect(URLDomain.normalizeServer("links.example.org")?.absoluteString == "https://links.example.org")
        #expect(URLDomain.normalizeServer("https://links.example.org/bookmarks?q=x")?.absoluteString == "https://links.example.org")
        #expect(URLDomain.normalizeServer("http://192.168.1.10:9090/")?.absoluteString == "http://192.168.1.10:9090")
        #expect(URLDomain.normalizeServer("https://home.example.org/linkding/settings")?.absoluteString == "https://home.example.org/linkding")
        #expect(URLDomain.normalizeServer("ftp://x") == nil)
        #expect(URLDomain.normalizeServer("   ") == nil)
    }
}

@Suite("RelativeAge")
struct RelativeAgeTests {
    // The units, not the rendered strings: Xcode Cloud runs the simulator in
    // English, where the same age reads "2mo" instead of "2 mois".
    @Test("compact units")
    func units() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-30), now: now) == .now)
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-3 * 3600), now: now) == .hours(3))
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-2 * 86_400), now: now) == .days(2))
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-8 * 86_400), now: now) == .weeks(1))
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-65 * 86_400), now: now) == .months(2))
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-400 * 86_400), now: now) == .years(1))
    }

    @Test("thresholds sit on the right side of each boundary")
    func boundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-59 * 60), now: now) == .now)
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-60 * 60), now: now) == .hours(1))
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-6 * 86_400), now: now) == .days(6))
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-7 * 86_400), now: now) == .weeks(1))
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-29 * 86_400), now: now) == .weeks(4))
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-30 * 86_400), now: now) == .months(1))
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-364 * 86_400), now: now) == .months(12))
        #expect(RelativeAge.unit(from: now.addingTimeInterval(-365 * 86_400), now: now) == .years(1))
    }

    @Test("a rendered age is never empty and carries its number")
    func rendering() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let twoDays = RelativeAge.string(from: now.addingTimeInterval(-2 * 86_400), now: now)
        #expect(twoDays.contains("2"))
        #expect(!RelativeAge.string(from: now.addingTimeInterval(-30), now: now).isEmpty)
    }
}
