import SwiftUI

/// Suggestion logic of the tag field, kept pure for the tests.
enum TagSuggestions {
    struct Result: Equatable {
        /// Typed text that matches no existing tag: offered as "+ new".
        var creatable: String?
        var matches: [String]
    }

    static func compute(input: String, pool: [String], selected: [String], limit: Int = 6) -> Result {
        let query = TagNormalizer.normalize(input)
        let taken = Set(selected.map(TagNormalizer.normalize))
        var seen = Set<String>()
        var matches = pool.filter { candidate in
            let c = TagNormalizer.normalize(candidate)
            guard !c.isEmpty, !taken.contains(c), seen.insert(c).inserted else { return false }
            return query.isEmpty || c.contains(query)
        }
        if !query.isEmpty {
            matches.sort { a, b in
                let ap = a.hasPrefix(query), bp = b.hasPrefix(query)
                if ap != bp { return ap }
                return a.localizedStandardCompare(b) == .orderedAscending
            }
        }
        let exists = pool.contains { TagNormalizer.normalize($0) == query }
        let creatable = (!query.isEmpty && !exists && !taken.contains(query)) ? query : nil
        return Result(creatable: creatable, matches: Array(matches.prefix(limit)))
    }

    /// Most used tags first, then every other known tag.
    static func pool(usage: [(name: String, count: Int)], known: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in usage.map(\.name) + known where seen.insert(name).inserted { result.append(name) }
        return result
    }
}

/// Chips plus an inline text field in a flow layout, with a row of
/// suggestions (existing tags, or "+ new" when nothing matches). Enter or a
/// comma validates, backspace on an empty field removes the last chip.
struct TagField: View {
    @Binding var tags: [String]
    var suggestionPool: [String]
    var autoTags: [String] = []

    @State private var input = ""
    @FocusState private var focused: Bool

    private var suggestions: TagSuggestions.Result {
        TagSuggestions.compute(input: input, pool: autoTags + suggestionPool, selected: tags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(name: tag, style: .editable) { remove(tag) }
                }
                TextField(tags.isEmpty ? String(localized: "Ajouter un tag") : "", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit { commit(input) }
                    .onChange(of: input) { _, value in
                        if value.contains(",") { commit(value) }
                    }
                    .onKeyPress(.delete) {
                        guard input.isEmpty, !tags.isEmpty else { return .ignored }
                        tags.removeLast()
                        return .handled
                    }
                    .frame(minWidth: 90, minHeight: 26)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            let s = suggestions
            if s.creatable != nil || !s.matches.isEmpty {
                Divider().padding(.vertical, 8)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        if let new = s.creatable {
                            Button { add(new) } label: {
                                Label(new, systemImage: "plus")
                                    .font(.subheadline.weight(.medium))
                                    .labelStyle(.titleAndIcon)
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .foregroundStyle(.white)
                                    .background(Color.accentColor, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(s.matches, id: \.self) { tag in
                            Button { add(tag) } label: {
                                Text(tag)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .foregroundStyle(Color.accentColor)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, 4)
            }
        }
    }

    private func commit(_ raw: String) {
        for part in raw.split(separator: ",") { add(String(part)) }
        input = ""
    }

    private func add(_ raw: String) {
        let tag = TagNormalizer.normalize(raw)
        guard !tag.isEmpty else { return }
        if !tags.contains(tag) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { tags.append(tag) }
        }
        input = ""
    }

    private func remove(_ tag: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { tags.removeAll { $0 == tag } }
    }
}
