import SwiftUI
import UIKit

/// AsyncImage's presentation with the same approved TLS certificates as the
/// API. External image origins keep ordinary system trust and no credentials.
struct ServerImage<Content: View>: View {
    let url: URL
    @ViewBuilder var content: (AsyncImagePhase) -> Content
    @AppStorage(SettingsKey.serverURL, store: AppGroup.defaults) private var server = ""
    @State private var phase: AsyncImagePhase = .empty

    private struct Request: Hashable {
        let url: URL
        let server: String
    }

    var body: some View {
        content(phase)
            .task(id: Request(url: url, server: server)) {
                phase = .empty
                do {
                    let data = try await ServerImageLoader.shared.data(from: url, serverURL: URL(string: server))
                    try Task.checkCancellation()
                    guard let image = UIImage(data: data) else { throw LinkdingError.decoding }
                    phase = .success(Image(uiImage: image))
                } catch {
                    if !Task.isCancelled { phase = .failure(error) }
                }
            }
    }
}

final class ServerImageLoader: @unchecked Sendable {
    static let shared = ServerImageLoader()
    private let lock = NSLock()
    private var pinnedSession: (URL, URLSession)?

    static func sameOrigin(_ url: URL, _ serverURL: URL) -> Bool {
        func port(_ url: URL) -> Int? { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return url.scheme?.lowercased() == serverURL.scheme?.lowercased()
            && url.host()?.lowercased() == serverURL.host()?.lowercased()
            && port(url) == port(serverURL)
    }

    func data(from url: URL, serverURL: URL?) async throws -> Data {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw LinkdingError.invalidURL }
        let session: URLSession
        if let serverURL, Self.sameOrigin(url, serverURL) {
            session = self.session(for: serverURL)
        } else {
            session = .shared
        }
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw LinkdingError.decoding
        }
        return data
    }

    private func session(for origin: URL) -> URLSession {
        lock.withLock {
            if let (previous, session) = pinnedSession, previous == origin { return session }
            pinnedSession?.1.invalidateAndCancel()
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 10
            // Static linkding images do not need the API token. Do not attach
            // it to image requests or forward it through redirects.
            let session = URLSession(configuration: configuration,
                                     delegate: ServerTrustDelegate(store: .shared, pinnedOrigin: origin), delegateQueue: nil)
            pinnedSession = (origin, session)
            return session
        }
    }
}
