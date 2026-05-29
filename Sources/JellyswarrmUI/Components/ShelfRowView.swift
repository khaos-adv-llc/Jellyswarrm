// MARK: - ShelfRowView.swift

// Jellyswarrm — LGPL-2.1-or-later
// Reusable horizontal shelf with title header. On tvOS every row carries
// `.focusSection()` so the focus engine moves between rows on Up/Down rather
// than diagonally hopping into the next visible card.

import SwiftUI

public struct ShelfRowView<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    let cardBuilder: (Item) -> Card

    public init(
        title: String,
        items: [Item],
        @ViewBuilder cardBuilder: @escaping (Item) -> Card
    ) {
        self.title = title
        self.items = items
        self.cardBuilder = cardBuilder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(sectionHeaderFont)
                .fontWeight(.bold)
                .foregroundStyle(AppleTVTheme.labelPrimary)
                .padding(.leading, AppleTVTheme.shelfHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppleTVTheme.cardSpacing) {
                    ForEach(items) { item in
                        cardBuilder(item)
                    }
                }
                .padding(.horizontal, AppleTVTheme.shelfHorizontalPadding)
                // Vertical padding so the focus scale doesn't clip into peers.
                .padding(.vertical, 20)
            }
        }
        #if os(tvOS)
            // Required so Up/Down hops between rows instead of diagonally
            // skating into a card in the next row.
            .focusSection()
        #endif
    }

    private var sectionHeaderFont: Font {
        #if os(tvOS)
            return AppleTVTheme.sectionHeaderFont
        #else
            return .title2
        #endif
    }
}
