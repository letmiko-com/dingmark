import SwiftUI

/// Notes are Markdown. `AttributedString(markdown:)` handles the inline
/// syntax (bold, links, code); headings and bullets are laid out line by line
/// so the block structure survives without an HTML renderer.
struct MarkdownNotesView: View {
    let notes: String

    private struct Line: Identifiable {
        enum Kind { case heading, bullet, paragraph }
        let id: Int
        let kind: Kind
        let text: String
    }

    private var lines: [Line] {
        notes.components(separatedBy: .newlines).enumerated().compactMap { index, raw in
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let range = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                return Line(id: index, kind: .heading, text: String(trimmed[range.upperBound...]))
            }
            if let range = trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                return Line(id: index, kind: .bullet, text: String(trimmed[range.upperBound...]))
            }
            return Line(id: index, kind: .paragraph, text: trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                switch line.kind {
                case .heading:
                    Text(inline(line.text)).font(.body.weight(.semibold))
                case .bullet:
                    // One element per item: the glyph alone would be a tiny
                    // selectable target and a meaningless VoiceOver stop.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.tertiary).accessibilityHidden(true)
                        Text(inline(line.text))
                    }
                    .padding(.leading, 4)
                    .accessibilityElement(children: .combine)
                case .paragraph:
                    Text(inline(line.text))
                }
            }
        }
        .font(.body)
        .textSelection(.enabled)
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
