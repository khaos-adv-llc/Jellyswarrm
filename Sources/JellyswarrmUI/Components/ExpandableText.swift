// MARK: - ExpandableText.swift

// Jellyswarrm — GPL v3 with App Store exception
// Long descriptions get truncated with a "Show more" toggle so they don't run
// off the screen on phones. Threshold is character count — cheap and good enough.

import SwiftUI

public struct ExpandableText: View {
    let text: String
    var collapsedLineLimit: Int = 3
    var expandThreshold: Int = 150
    var font: Font = .subheadline
    var foregroundStyle: AnyShapeStyle = AnyShapeStyle(.secondary)

    @State private var isExpanded = false

    public init(
        _ text: String,
        collapsedLineLimit: Int = 3,
        expandThreshold: Int = 150,
        font: Font = .subheadline
    ) {
        self.text = text
        self.collapsedLineLimit = collapsedLineLimit
        self.expandThreshold = expandThreshold
        self.font = font
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(font)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)

            if text.count > expandThreshold {
                Button(isExpanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
                .font(.caption)
                .foregroundStyle(.indigo)
                #if !os(tvOS)
                    .buttonStyle(.plain)
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
