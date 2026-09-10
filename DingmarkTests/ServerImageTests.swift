import Foundation
import Testing
@testable import Dingmark

@Suite("Image server trust scope")
struct ServerImageTests {
    @Test("approved image trust stays on the configured scheme, host and port")
    func originIsolation() throws {
        let server = try #require(URL(string: "https://links.example.org:8443/linkding"))
        #expect(ServerImageLoader.sameOrigin(URL(string: "https://links.example.org:8443/static/favicon.png")!, server))
        #expect(!ServerImageLoader.sameOrigin(URL(string: "https://other.example.org:8443/static/favicon.png")!, server))
        #expect(!ServerImageLoader.sameOrigin(URL(string: "https://links.example.org/static/favicon.png")!, server))
        #expect(!ServerImageLoader.sameOrigin(URL(string: "http://links.example.org:8443/static/favicon.png")!, server))
        #expect(ServerImageLoader.sameOrigin(URL(string: "https://links.example.org:443/a")!, URL(string: "https://links.example.org")!))
    }

    @Test("redirect challenges outside the image origin cannot use an approved pin")
    func redirectIsolation() {
        let trust = TrustStore(defaults: UserDefaults(suiteName: "image-trust-test-\(UUID())")!)
        let delegate = ServerTrustDelegate(store: trust, pinnedOrigin: URL(string: "https://links.example.org:8443")!)
        #expect(delegate.permitsPin(host: "links.example.org", port: 8443, scheme: "https"))
        #expect(!delegate.permitsPin(host: "links.example.org", port: 443, scheme: "https"))
        #expect(!delegate.permitsPin(host: "other.example.org", port: 8443, scheme: "https"))
        #expect(!delegate.permitsPin(host: "links.example.org", port: 8443, scheme: "http"))
    }
}
