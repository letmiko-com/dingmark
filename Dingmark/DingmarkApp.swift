import SwiftUI

@main
struct DingmarkApp: App {
    @State private var session: Session
    @State private var store: BookmarkStore
    @State private var router = AppRouter()

    init() {
        // `-demo` (launch argument) or DINGMARK_DEMO=1 serves the design
        // fixtures without a server: previews, screenshots, UI tests.
        let process = ProcessInfo.processInfo
        let demo = process.arguments.contains("-demo") || process.environment["DINGMARK_DEMO"] == "1"
        let session = Session(demo: demo)
        _session = State(initialValue: session)
        // The demo keeps its cache and its list preferences to itself: the
        // App Group file feeds the widgets and the offline list of the real
        // server, and a sort left by one demo run must not shape the next
        // (screenshots and UI tests expect the default order).
        let cache = demo
            ? BookmarkCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("dingmark-demo-cache.json"))
            : BookmarkCache.shared
        let defaults = demo ? Self.demoDefaults() : AppGroup.defaults
        _store = State(initialValue: BookmarkStore(api: session.makeAPI(), cache: cache, cacheSessionID: session.cacheSessionID, defaults: defaults))
    }

    /// A suite emptied at every demo launch.
    private static func demoDefaults() -> UserDefaults {
        let name = "app.letmiko.dingmark.demo"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(store)
                .environment(router)
                .tint(.dingmarkAccent)
                .onOpenURL { router.handle($0) }
        }
    }
}
