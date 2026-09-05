import SwiftUI

struct SettingsScreen: View {
    var body: some View {
        NavigationStack {
            SettingsForm()
        }
    }
}

/// Server, adding, display, about. Stored in the App Group defaults so the
/// share extension and the widgets read the same values.
struct SettingsForm: View {
    @Environment(Session.self) private var session
    @Environment(BookmarkStore.self) private var store
    @AppStorage(SettingsKey.defaultTags, store: AppGroup.defaults) private var defaultTagsRaw = ""
    @AppStorage(SettingsKey.unreadByDefault, store: AppGroup.defaults) private var unreadByDefault = true
    @AppStorage(SettingsKey.openLinksInApp, store: AppGroup.defaults) private var openInApp = true
    @AppStorage(SettingsKey.listDensity, store: AppGroup.defaults) private var densityRaw = ListDensity.comfortable.rawValue

    @State private var confirmSignOut = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section("Serveur") {
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.host ?? "—")
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if !session.isDemo {
                    Button("Changer de serveur") { confirmSignOut = true }
                }
            }

            Section("Ajout") {
                NavigationLink {
                    DefaultTagsView()
                } label: {
                    LabeledContent("Tags par défaut", value: defaultTagsSummary)
                }
                Toggle("Non lu par défaut", isOn: $unreadByDefault)
            }

            Section("Affichage") {
                Picker("Ouvrir les liens", selection: $openInApp) {
                    Text("Dans l’app").tag(true)
                    Text("Safari").tag(false)
                }
                HStack {
                    Text("Liste")
                    Spacer()
                    Picker("Liste", selection: $densityRaw) {
                        Text("Compacte").tag(ListDensity.compact.rawValue)
                        Text("Avec description").tag(ListDensity.comfortable.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            Section {
                LabeledContent("Version", value: version)
                if let url = URL(string: "https://github.com/sissbruecker/linkding") {
                    Link(destination: url) {
                        LabeledContent("linkding", value: "github.com")
                    }
                }
            } header: {
                Text("À propos")
            } footer: {
                Text("Dingmark · Letmiko")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .navigationTitle("Réglages")
        .confirmationDialog("Changer de serveur ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) {
                store.reset()
                session.signOut()
            }
        } message: {
            Text("Le jeton est retiré de cet appareil et le cache des favoris effacé.")
        }
    }

    private var subtitle: String {
        let count = store.hasLoadedOnce ? store.counts.all : (session.bookmarkCount ?? 0)
        return session.isDemo ? String(localized: "Démonstration · \(count) favoris") : String(localized: "linkding · \(count) favoris")
    }

    private var defaultTagsSummary: String {
        let tags = TagList.parse(defaultTagsRaw)
        return tags.isEmpty ? String(localized: "Aucun") : tags.joined(separator: ", ")
    }
}

struct DefaultTagsView: View {
    @Environment(BookmarkStore.self) private var store
    @AppStorage(SettingsKey.defaultTags, store: AppGroup.defaults) private var defaultTagsRaw = ""

    var body: some View {
        Form {
            Section {
                TagField(tags: Binding(get: { TagList.parse(defaultTagsRaw) }, set: { defaultTagsRaw = TagList.join($0) }),
                         suggestionPool: TagSuggestions.pool(usage: store.tagUsage, known: store.knownTags))
            } footer: {
                Text("Ajoutés à chaque nouveau favori, y compris depuis la share extension.")
            }
        }
        .navigationTitle("Tags par défaut")
        .navigationBarTitleDisplayMode(.inline)
    }
}
