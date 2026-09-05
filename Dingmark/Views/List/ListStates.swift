import SwiftUI

/// Six fake rows, redacted, pulsing between 55 % and 100 % opacity. Never a
/// full-screen spinner.
struct LoadingPlaceholderList: View {
    var density: ListDensity = .comfortable
    @State private var pulse = false

    var body: some View {
        List(DemoData.placeholders) { bookmark in
            BookmarkRow(bookmark: bookmark, density: density)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
        .listStyle(.plain)
        .redacted(reason: .placeholder)
        .disabled(true)
        .opacity(pulse ? 1 : 0.55)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel(Text("Chargement"))
    }
}

struct EmptyBookmarksView: View {
    var onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Aucun favori", systemImage: "tray")
        } description: {
            Text("Ajoutez un lien ici ou partagez une page depuis Safari.")
        } actions: {
            Button("Ajouter un favori", action: onAdd)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
    }
}

struct NoResultsView: View {
    let query: String
    var onClear: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Aucun résultat", systemImage: "magnifyingglass")
        } description: {
            Text("Aucun favori ne correspond à « \(query) ».")
        } actions: {
            Button("Effacer la recherche", action: onClear)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }
}

struct ServerErrorView: View {
    let error: LinkdingError
    var onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            Button("Réessayer", action: onRetry)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }

    private var title: LocalizedStringKey {
        switch error {
        case .unauthorized: "Jeton refusé"
        case .untrustedCertificate: "Certificat non reconnu"
        default: "Serveur injoignable"
        }
    }

    private var symbol: String {
        switch error {
        case .unauthorized: "lock.fill"
        default: "icloud.slash"
        }
    }

    private var message: String {
        switch error {
        case .unreachable(let host), .untrustedCertificate(let host):
            String(localized: "\(host) n’a pas répondu. Les favoris en cache restent consultables.")
        case .unauthorized:
            String(localized: "Le serveur a répondu 401. Vérifiez le jeton dans Réglages › Intégrations.")
        default:
            error.userMessage
        }
    }
}

/// Footnote line above the cached list when the server is unreachable.
struct OfflineBanner: View {
    let lastSync: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Hors ligne · dernière synchro \(lastSync, format: .relative(presentation: .named))")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.screenMargin + 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
}
