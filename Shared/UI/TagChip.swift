import SwiftUI

enum TagChipStyle {
    /// 20 pt, footnote, tertiary fill, secondary text (list rows).
    case cell
    /// 26 pt, subheadline, tertiary fill, accent text (detail).
    case detail
    /// 26 pt, subheadline medium, accent fill, white text, removable.
    case editable
}

struct TagChip: View {
    let name: String
    var style: TagChipStyle = .cell
    var onRemove: (() -> Void)? = nil

    var body: some View {
        switch style {
        case .cell:
            Text(name)
                .font(.footnote)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                .foregroundStyle(.secondary)
                .background(Color(.tertiarySystemFill), in: Capsule())
        case .detail:
            Text(name)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .foregroundStyle(Color.accentColor)
                .background(Color(.tertiarySystemFill), in: Capsule())
        case .editable:
            HStack(spacing: 4) {
                Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 20, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Retirer le tag \(name)"))
            }
            .padding(.leading, 10)
            .padding(.trailing, 2)
            .frame(height: 26)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: Capsule())
        }
    }
}
