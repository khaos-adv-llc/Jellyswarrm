// MARK: - PosterCardModifier.swift

// Jellyswarrm — LGPL-2.1-or-later
// 2:3 portrait poster framing with rounded corners. Use instead of ad-hoc
// frame+clipShape pairs so the aspect ratio and corner radius stay consistent
// across MediaCardView, SeerrMediaCardView, and any future card view.

import SwiftUI

public struct PosterCardModifier: ViewModifier {
    let width: CGFloat
    let cornerRadius: CGFloat

    public init(width: CGFloat, cornerRadius: CGFloat = 10) {
        self.width = width
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

public extension View {
    func posterCard(width: CGFloat, cornerRadius: CGFloat = 10) -> some View {
        modifier(PosterCardModifier(width: width, cornerRadius: cornerRadius))
    }
}
