// MARK: - AppleTVTheme.swift

// Jellyswarrm — LGPL-2.1-or-later
// Design tokens matching Apple TV app fidelity.

import SwiftUI

public enum AppleTVTheme {
    // MARK: - Layout

    /// Hero takes 42% of screen height — ~454pt at 1080p.
    public static let heroHeightRatio: CGFloat = 0.42

    /// Apple's recommended safe zone for tvOS edges.
    public static let safeInset: CGFloat = 60

    public static var shelfHorizontalPadding: CGFloat {
        #if os(tvOS)
            return 60
        #elseif os(macOS)
            return 32
        #else
            return 20
        #endif
    }

    /// Vertical gap between shelf rows.
    public static let shelfSpacing: CGFloat = 48

    /// Horizontal gap between cards in a row.
    public static let cardSpacing: CGFloat = 24

    // MARK: - Card sizes (tvOS — portrait 2:3)

    public static let cardWidthTVOS: CGFloat = 250
    public static let cardHeightTVOS: CGFloat = 375

    // MARK: - Card sizes (tvOS — wide 16:9, episodes/continue watching)

    public static let wideCardWidthTVOS: CGFloat = 440
    public static let wideCardHeightTVOS: CGFloat = 247

    // MARK: - Card sizes (iOS / iPadOS)

    public static let cardWidthIOS: CGFloat = 120
    public static let cardHeightIOS: CGFloat = 180

    // MARK: - Focus behavior

    /// Scale factor on focus — matches Apple TV app's 1.12–1.15.
    public static let focusScale: CGFloat = 1.13
    public static let focusGlowOpacity: Double = 0.4
    public static let focusGlowRadius: CGFloat = 20
    /// Dim unfocused cards slightly so the focused poster stands out.
    public static let unfocusedOpacity: Double = 0.85
    public static let focusAnimDuration: Double = 0.15

    // MARK: - Colors

    public static let background = Color(red: 0.06, green: 0.06, blue: 0.06)
    public static let cardBackground = Color(white: 0.12)
    public static let labelPrimary = Color.white
    public static let labelSecondary = Color(white: 0.65)
    public static let accentBlue = Color(red: 0.0, green: 0.48, blue: 1.0)

    // MARK: - Typography (SF Pro, Apple TV app sizing)

    public static let heroTitleFont = Font.system(size: 52, weight: .bold, design: .default)
    public static let heroSubtitleFont = Font.system(size: 28, weight: .regular)
    public static let sectionHeaderFont = Font.system(size: 34, weight: .bold)
    public static let cardTitleFont = Font.system(size: 22, weight: .medium)
    public static let cardSubtitleFont = Font.system(size: 18, weight: .regular)
}
