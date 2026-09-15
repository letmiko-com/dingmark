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
    @AppStorage(SettingsKey.readerMode, store: AppGroup.defaults) private var readerMode = true
    @AppStorage(SettingsKey.markReadOnOpen, store: AppGroup.defaults) private var markReadOnOpen = true

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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Serveur \(session.host ?? ""), \(subtitle)"))
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

            Section {
                Picker("Ouvrir les liens", selection: $openInApp) {
                    Text("Dans l’app").tag(true)
                    Text("Safari").tag(false)
                }
                Toggle("Mode lecteur automatique", isOn: $readerMode)
                    .disabled(!openInApp)
                Toggle("Marquer lu à l’ouverture", isOn: $markReadOnOpen)
            } header: {
                Text("Lecture")
            } footer: {
                Text("Le mode lecteur s’applique aux pages ouvertes dans l’app, quand Safari le propose.")
            }

            Section("Affichage") {
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
                if let url = URL(string: SupportLinks.help) {
                    Link(destination: url) {
                        Label("Aide et questions fréquentes", systemImage: "questionmark.circle")
                    }
                }
                if let url = URL(string: SupportLinks.issues) {
                    Link(destination: url) {
                        Label("Signaler un problème sur GitHub", systemImage: "ladybug")
                    }
                }
                if let url = SupportLinks.reportMail(version: version) {
                    Link(destination: url) {
                        Label("Écrire à Letmiko", systemImage: "envelope")
                    }
                }
            } header: {
                Text("Support")
            } footer: {
                Text("Le message pré-rempli indique la version de l’app et d’iOS. Votre jeton d’API n’y figure jamais.")
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

/// Public support channels: the site's help page, the repository's issues
/// and a mail whose body carries the app and system versions, nothing else.
enum SupportLinks {
    static let help = "https://dingmark.letmiko.app/support"
    static let issues = "https://github.com/letmiko-com/dingmark/issues"
    static let contact = "contact@letmiko.com"

    static func reportMail(version: String, system: String = UIDevice.current.systemVersion,
                           model: String = UIDevice.current.model) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = contact
        components.queryItems = [
            URLQueryItem(name: "subject", value: String(localized: "Dingmark \(version) : problème")),
            URLQueryItem(name: "body", value: String(localized: "Dingmark \(version), iOS \(system), \(model).\n\nCe qui se passe :\n\nCe que j’attendais :\n")),
        ]
        return components.url
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
