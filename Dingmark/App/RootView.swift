import SwiftUI

/// Login until a server is configured, then the phone tab bar or the iPad
/// split view. Also owns the cache load, the initial refresh and the toast.
struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(BookmarkStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !session.isConnected {
                LoginView()
            } else if sizeClass == .regular {
                SplitRootView()
            } else {
                PhoneRootView()
            }
        }
        .task(id: session.isConnected) {
            if session.isConnected {
                store.configure(api: session.makeAPI(), cacheSessionID: session.cacheSessionID)
                store.loadFromCache()
                await store.refresh()
                guard !Task.isCancelled, session.isConnected else { return }
                let active = store.bookmarks.filter { !$0.isArchived }.count
                if store.loadError == nil, active > 0 { session.recordBookmarkCount(active) }
            } else {
                store.configure(api: nil)
                store.reset()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back in the foreground: pick up what the share extension, a
            // widget or another device saved meanwhile. The initial load
            // is still running at launch, refresh() ignores the overlap.
            if phase == .active, session.isConnected, store.hasLoadedOnce {
                Task { await store.refresh() }
            }
        }
        .overlay(alignment: .top) { ToastView() }
        .sensoryFeedback(.success, trigger: store.successCount)
        .sensoryFeedback(.impact(weight: .medium), trigger: store.destructiveCount)
    }
}

struct PhoneRootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Favoris", systemImage: "bookmark", value: AppRouter.Tab.bookmarks) {
                BookmarkListScreen()
            }
            Tab("Tags", systemImage: "tag", value: AppRouter.Tab.tags) {
                TagListScreen()
            }
            Tab("Réglages", systemImage: "gear", value: AppRouter.Tab.settings) {
                SettingsScreen()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// Discreet confirmation banner (saved, archived, deleted, URL copied).
struct ToastView: View {
    @Environment(BookmarkStore.self) private var store

    var body: some View {
        if let toast = store.toast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                Text(toast.message).font(.subheadline.weight(.medium))
            }
            .padding(.leading, 14)
            .padding(.trailing, 18)
            .frame(height: 44)
            .glassEffect(.regular, in: Capsule())
            .padding(.top, 8)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(1.8))
                if store.toast?.id == toast.id {
                    withAnimation(.easeOut(duration: 0.2)) { store.toast = nil }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast.id)
        }
    }
}
