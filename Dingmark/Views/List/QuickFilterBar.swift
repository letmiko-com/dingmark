import SwiftUI

extension QuickFilter {
    var title: LocalizedStringKey {
        switch self {
        case .all: "Tous"
        case .unread: "Non lus"
        case .archived: "Archivés"
        case .untagged: "Sans tag"
        }
    }

    var symbol: String {
        switch self {
        case .all: "bookmark"
        case .unread: "envelope.badge"
        case .archived: "archivebox"
        case .untagged: "tag.slash"
        }
    }
}

/// Horizontal row of 32 pt capsules with counters. The selected capsule
/// slides between filters (matchedGeometryEffect, spring 0.35 / 0.85). The
/// only custom control of the screen: a segmented picker neither scrolls nor
/// shows counters.
struct QuickFilterBar: View {
    @Binding var selection: QuickFilter
    let counts: FilterCounts
    @Namespace private var pill

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(QuickFilter.allCases) { filter in
                    let selected = filter == selection
                    let count = counts.value(for: filter)
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selection = filter }
                    } label: {
                        HStack(spacing: 6) {
                            Text(filter.title).font(.subheadline.weight(.medium))
                            if count > 0 {
                                Text(count, format: .number).font(.footnote).opacity(0.7)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: Metrics.filterHeight)
                        .foregroundStyle(selected ? Color.onAccent : Color.primary)
                        .background {
                            if selected {
                                Capsule().fill(Color.dingmarkAccent).matchedGeometryEffect(id: "pill", in: pill)
                            } else {
                                Capsule().fill(Color(.tertiarySystemFill))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Metrics.screenMargin)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
