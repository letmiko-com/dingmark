import Foundation
import Observation

/// Tab selection and deep links (`dingmark://add`, `dingmark://bookmark/<id>`).
@MainActor @Observable
final class AppRouter {
    enum Tab: Hashable { case bookmarks, tags, settings }

    struct AddRequest: Identifiable, Equatable {
        let id = UUID()
        var url: String?
        var title: String?
    }

    var tab: Tab = .bookmarks
    var addRequest: AddRequest?
    var pendingBookmarkID: Int?

    func showAdd(url: String? = nil, title: String? = nil) {
        tab = .bookmarks
        addRequest = AddRequest(url: url, title: title)
    }

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "dingmark" else { return }
        switch url.host()?.lowercased() {
        case "add":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            showAdd(url: items.first { $0.name == "url" }?.value, title: items.first { $0.name == "title" }?.value)
        case "bookmark":
            if let id = Int(url.lastPathComponent) {
                tab = .bookmarks
                pendingBookmarkID = id
            }
        default:
            break
        }
    }
}
