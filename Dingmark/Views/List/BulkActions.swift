import SwiftUI

extension View {
    /// Multiple selection of a bookmark list: a "Sélectionner" button enters
    /// edit mode, the bottom bar then offers mark read, archive (or
    /// unarchive on the archived list), add tags and delete. Every action
    /// goes through the store's ordered writes and leaves edit mode.
    func bulkSelection(selection: Binding<Set<Int>>, editMode: Binding<EditMode>, visibleIDs: [Int], archivedContext: Bool) -> some View {
        modifier(BulkSelectionModifier(selection: selection, editMode: editMode, visibleIDs: visibleIDs, archivedContext: archivedContext))
    }
}

private struct BulkSelectionModifier: ViewModifier {
    @Binding var selection: Set<Int>
    @Binding var editMode: EditMode
    let visibleIDs: [Int]
    let archivedContext: Bool

    @Environment(BookmarkStore.self) private var store
    @State private var showTagSheet = false
    @State private var confirmDelete = false

    private var editing: Bool { editMode.isEditing }
    private var allSelected: Bool { !visibleIDs.isEmpty && Set(visibleIDs).isSubset(of: selection) }

    func body(content: Content) -> some View {
        content
            .environment(\.editMode, $editMode)
            // The action bar takes the place of the tab bar while selecting.
            .toolbar(editing ? .hidden : .automatic, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editing ? "OK" : "Sélectionner") {
                        withAnimation { editing ? finish() : (editMode = .active) }
                    }
                    .disabled(!editing && visibleIDs.isEmpty)
                }
                if editing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(allSelected ? "Aucun" : "Tout") {
                            withAnimation { selection = allSelected ? [] : Set(visibleIDs) }
                        }
                        .disabled(visibleIDs.isEmpty)
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            store.markRead(ids: selection)
                            finish()
                        } label: {
                            Label("Marquer lus", systemImage: "envelope.open")
                        }
                        .disabled(selection.isEmpty)
                        Spacer()
                        Button {
                            store.setArchived(ids: selection, !archivedContext)
                            finish()
                        } label: {
                            Label(archivedContext ? "Désarchiver" : "Archiver", systemImage: "archivebox")
                        }
                        .disabled(selection.isEmpty)
                        Spacer()
                        Button {
                            showTagSheet = true
                        } label: {
                            Label("Ajouter des tags", systemImage: "tag")
                        }
                        .disabled(selection.isEmpty)
                        Spacer()
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                        .disabled(selection.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showTagSheet) {
                BulkTagSheet(ids: selection) { finish() }
            }
            .confirmationDialog(Text("Supprimer \(selection.count) favoris ?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    store.delete(ids: selection)
                    finish()
                }
            } message: {
                Text("Cette action retire définitivement les favoris du serveur.")
            }
    }

    private func finish() {
        selection.removeAll()
        editMode = .inactive
    }
}

/// Tags to add to the selection; the bookmarks keep the tags they have.
struct BulkTagSheet: View {
    let ids: Set<Int>
    var onDone: () -> Void

    @Environment(BookmarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TagField(tags: $tags, suggestionPool: TagSuggestions.pool(usage: store.tagUsage, known: store.knownTags))
                } footer: {
                    Text("Ajoutés aux \(ids.count) favoris sélectionnés. Leurs tags actuels sont conservés.")
                }
            }
            .navigationTitle("Ajouter des tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        store.addTags(tags, to: ids)
                        dismiss()
                        onDone()
                    }
                    .disabled(tags.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
