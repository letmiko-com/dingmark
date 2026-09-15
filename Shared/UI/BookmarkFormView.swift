import SwiftUI
import UniformTypeIdentifiers

/// Add / edit form: URL (with paste button and inline fetch spinner), title,
/// description, tags, toggles, Markdown notes. Presented as a sheet by the
/// app; the share extension reuses the sections in its compact sheet.
struct BookmarkFormView: View {
    @Bindable var model: BookmarkFormModel
    var onSaved: (Bookmark) -> Void
    var onCancel: () -> Void

    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                if let existing = model.existing, model.savesExisting {
                    Section {
                        DuplicateWarning(existing: existing)
                    }
                }
                BookmarkFormSections(model: model)
                if let error = model.saveError {
                    Section {
                        Label(String(localized: "Enregistrement impossible : \(error.userMessage)"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(model.isEditing ? Text("Modifier") : Text("Nouveau favori"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if saving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(model.savesExisting ? "Mettre à jour" : "Enregistrer").fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(!model.canSave || saving)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            if let saved = try? await model.save() {
                onSaved(saved)
            }
        }
    }
}

/// The form sections without the navigation chrome (shared with the share
/// extension, which lays them out in cards).
struct BookmarkFormSections: View {
    @Bindable var model: BookmarkFormModel

    var body: some View {
        Section {
            HStack(spacing: 8) {
                TextField("URL", text: $model.url)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if model.isFetching {
                    ProgressView().controlSize(.small)
                } else if model.showsPasteButton {
                    PasteButton(supportedContentTypes: [.url, .plainText]) { providers in model.paste(providers) }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .tint(Color.accentColor)
                }
            }
            TextField("Titre", text: $model.title)
                .opacity(model.isFetching ? 0.4 : 1)
            TextField("Description", text: $model.description, axis: .vertical)
                .lineLimit(2...6)
                .opacity(model.isFetching ? 0.4 : 1)
        }
        Section("Tags") {
            TagField(tags: $model.tags, suggestionPool: model.suggestionPool, autoTags: model.autoTags)
        }
        Section {
            Toggle("Marquer non lu", isOn: $model.unread)
            Toggle("Partager sur l’instance", isOn: $model.shared)
        }
        Section("Notes") {
            ZStack(alignment: .topLeading) {
                if model.notes.isEmpty {
                    Text("Markdown").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).accessibilityHidden(true)
                }
                TextEditor(text: $model.notes)
                    .accessibilityLabel(Text("Notes"))
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
            }
        }
    }
}

struct DuplicateWarning: View {
    let existing: Bookmark

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Déjà enregistré.").font(.subheadline.weight(.semibold))
                Text("Ajouté le \(existing.dateAdded, format: .dateTime.day().month(.abbreviated).year()). Les champs ont été pré-remplis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
