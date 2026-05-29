// MARK: - ShelfRowView.swift

// Jellyswarrm — GPL v3 with App Store exception
// Reusable horizontal shelf with title header and platform-aware padding,
// used to lay out card rows in the Apple TV–style home and discover screens.

import SwiftUI

public enum AppleTVTheme {
    /// Near-black global background used across the app to mimic the Apple TV app.
    public static let background = Color(red: 0.07, green: 0.07, blue: 0.07)

    public static var shelfHorizontalPadding: CGFloat {
        #if os(tvOS)
            return 60
        #elseif os(macOS)
            return 32
        #else
            return 20
        #endif
    }

    public static var shelfSpacing: CGFloat { 24 }
    public static var cardSpacing: CGFloat { 16 }
}

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
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, AppleTVTheme.shelfHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppleTVTheme.cardSpacing) {
                    ForEach(items) { item in
                        cardBuilder(item)
                    }
                }
                .padding(.horizontal, AppleTVTheme.shelfHorizontalPadding)
                .padding(.vertical, 4)
                #if os(tvOS)
                    // Cap the row height so a single oversized card cannot
                    // stretch the shelf and break vertical alignment with peers.
                    .frame(maxHeight: 220, alignment: .top)
                #endif
            }
        }
    }
}
