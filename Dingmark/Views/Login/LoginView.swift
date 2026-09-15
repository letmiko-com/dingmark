import SwiftUI

/// One screen: server, token, test. Errors are a card under the form, never
/// an alert. Self-signed certificates can be trusted explicitly.
struct LoginView: View {
    @Environment(Session.self) private var session

    private enum Phase: Equatable { case idle, testing, failed(Session.LoginFailure), connected }

    @State private var urlText = ""
    @State private var token = ""
    @State private var phase: Phase = .idle
    @FocusState private var focusedField: Field?

    private enum Field { case url, token }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    DingmarkIcon(size: 84)
                    Text("Dingmark").font(.title.bold())
                    Text("Connectez votre instance linkding. Aucun compte, aucun cloud.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                .padding(.bottom, 4)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                HStack(spacing: 12) {
                    Text("Serveur").frame(width: 96, alignment: .leading)
                    TextField("links.example.org", text: $urlText)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .url)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .token }
                }
                HStack(spacing: 12) {
                    Text("Jeton API").frame(width: 96, alignment: .leading)
                    SecureField("••••••••••••••••", text: $token)
                        // Not `.password`: iOS would offer to save an API
                        // token in Passwords after the login. `.oneTimeCode`
                        // is the documented way to opt out of that prompt.
                        .textContentType(.oneTimeCode)
                        .focused($focusedField, equals: .token)
                        .submitLabel(.go)
                        .onSubmit { test() }
                }
            } footer: {
                Text("Réglages › Intégrations › REST API sur votre instance linkding.")
            }

            if case .failed(let failure) = phase {
                Section {
                    LoginErrorCard(failure: failure) {
                        switch failure {
                        case .untrustedCertificate(let review):
                            session.trustCertificate(review)
                            test()
                        case .unreachable:
                            test()
                        default:
                            phase = .idle
                        }
                    }
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: phase)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: test) {
                    HStack(spacing: 8) {
                        if phase == .testing { ProgressView().tint(Color.onAccent) }
                        Text(buttonLabel).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.buttonHeight)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accentProminent()
                .disabled(phase == .testing || phase == .connected || urlText.trimmingCharacters(in: .whitespaces).isEmpty || token.isEmpty)
                Text("Letmiko").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Metrics.screenMargin)
            .padding(.top, 8)
            .background(Color(.systemGroupedBackground))
        }
        .onAppear {
            if urlText.isEmpty, let host = session.serverURL?.absoluteString { urlText = host }
        }
    }

    private var buttonLabel: LocalizedStringKey {
        switch phase {
        case .testing: "Connexion…"
        case .connected: "Connecté"
        default: "Tester la connexion"
        }
    }

    private func test() {
        guard phase != .testing else { return }
        focusedField = nil
        phase = .testing
        Task {
            if let failure = await session.connect(urlString: urlText, token: token) {
                phase = .failed(failure)
            } else {
                phase = .connected
                try? await Task.sleep(for: .milliseconds(500))
                session.commitLogin()
            }
        }
    }
}

struct LoginErrorCard: View {
    let failure: Session.LoginFailure
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body_).font(.footnote).foregroundStyle(.secondary)
                if case .untrustedCertificate(let review) = failure {
                    Text("Empreinte SHA-256").font(.caption.weight(.semibold))
                    Text(review.fingerprint)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let previous = review.previousFingerprint {
                        Text("Empreinte précédemment approuvée").font(.caption.weight(.semibold))
                        Text(previous)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Comparez cette empreinte avec celle de votre serveur avant de l’approuver.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let actionTitle {
                    Button(action: action) {
                        Text(actionTitle).font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 6)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: LocalizedStringKey {
        switch failure {
        case .invalidURL: "URL invalide"
        case .unauthorized: "Jeton refusé"
        case .credentialStorage: "Jeton non enregistré"
        case .untrustedCertificate(let review):
            review.previousFingerprint == nil ? "Certificat non reconnu" : "Le certificat du serveur a changé"
        case .unreachable: "Serveur injoignable"
        }
    }

    private var body_: String {
        switch failure {
        case .invalidURL: String(localized: "L’adresse doit commencer par https:// et pointer vers la racine de linkding.")
        case .unauthorized: String(localized: "Le serveur a répondu 401. Vérifiez le jeton dans Réglages › Intégrations.")
        case .credentialStorage: String(localized: "Le trousseau n’a pas pu enregistrer le jeton. Réessayez pour terminer la connexion.")
        case .untrustedCertificate(let review): String(localized: "Le certificat de \(review.host) n’a pas pu être validé.")
        case .unreachable: String(localized: "Aucune réponse en 10 s. Vérifiez l’adresse (http:// pour un serveur sans TLS) ou le VPN.")
        }
    }

    private var actionTitle: LocalizedStringKey? {
        switch failure {
        case .untrustedCertificate: "Faire confiance à ce serveur"
        case .unreachable: "Réessayer"
        default: nil
        }
    }
}
