// MARK: - MediaCardView.swift

// Jellyswarrm — LGPL-2.1-or-later
// Reusable poster card. tvOS focus is hand-rolled: scale + glow live ONLY on
// the poster image so the title below stays steady. `.buttonStyle(.plain)`
// plus `.focusEffectDisabled(true)` suppress the system white-box halo.

import JellyswarrmCore
import SwiftUI

public struct MediaCardView: View {
    let item: MediaItem
    let imageURL: URL?
    var showTitle: Bool = true
    var cardWidth: CGFloat = 150
    /// nil → tall portrait (cardWidth * 1.5). Use a specific height for wide
    /// (16:9) episode / continue-watching cards.
    var cardHeightOverride: CGFloat?

    public init(
        item: MediaItem,
        imageURL: URL?,
        showTitle: Bool = true,
        cardWidth: CGFloat = 150,
        cardHeight: CGFloat? = nil
    ) {
        self.item = item
        self.imageURL = imageURL
        self.showTitle = showTitle
        self.cardWidth = cardWidth
        self.cardHeightOverride = cardHeight
    }

    #if os(tvOS)
        @FocusState private var isFocused: Bool
    #else
        @State private var isHovered: Bool = false
    #endif

    private var focused: Bool {
        #if os(tvOS)
            return isFocused
        #else
            return isHovered
        #endif
    }

    private var cardHeight: CGFloat {
        cardHeightOverride ?? (cardWidth * 1.5)
    }

    private var cornerRadius: CGFloat { 12 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Poster — scale + glow applied ONLY here, never to title.
            posterImage
                .scaleEffect(focused ? AppleTVTheme.focusScale : 1.0)
                .shadow(
                    color: focused ? .white.opacity(AppleTVTheme.focusGlowOpacity) : .clear,
                    radius: focused ? AppleTVTheme.focusGlowRadius : 0
                )
                .animation(.easeInOut(duration: AppleTVTheme.focusAnimDuration), value: focused)

            if showTitle {
                cardLabel
            }
        }
        .frame(width: cardWidth)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            // Disable the system white outline; we draw our own scale + glow.
            .focusEffectDisabled(true)
        #else
            .onHover { isHovered = $0 }
        #endif
    }

    // MARK: - Poster

    @State private var imageLoaded = false

    private var posterImage: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(imageLoaded ? 1 : 0)
                        .onAppear {
                            withAnimation(.easeIn(duration: 0.3)) { imageLoaded = true }
                        }
                case .failure, .empty:
                    placeholderView
                @unknown default:
                    placeholderView
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipped()

            // Watched checkmark
            if item.userData?.played == true {
                watchedBadge
            }

            // Progress bar — partially-played items only
            if let pct = item.userData?.playedPercentage, pct > 0, pct < 100 {
                progressOverlay(fraction: pct / 100.0)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func progressOverlay(fraction: Double) -> some View {
        VStack {
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.black.opacity(0.4))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppleTVTheme.accentBlue)
                        .frame(width: geo.size.width * fraction, height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var watchedBadge: some View {
        HStack {
            Spacer()
            VStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.title3)
                    .padding(8)
                Spacer()
            }
        }
    }

    private var placeholderView: some View {
        ZStack {
            Rectangle().fill(AppleTVTheme.cardBackground)
            Image(systemName: "film")
                .font(.system(size: 40))
                .foregroundStyle(AppleTVTheme.labelSecondary)
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    // MARK: - Title / subtitle below poster (NOT scaled on focus)

    private var cardLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayTitle)
                .font(titleFont)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(
                    focused
                        ? AppleTVTheme.labelPrimary
                        : AppleTVTheme.labelPrimary.opacity(AppleTVTheme.unfocusedOpacity)
                )

            if let subtitle = cardSubtitle {
                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(AppleTVTheme.labelSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cardWidth, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var cardSubtitle: String? {
        if let year = item.productionYear { return String(year) }
        return nil
    }

    private var titleFont: Font {
        #if os(tvOS)
            return AppleTVTheme.cardTitleFont
        #else
            return .caption
        #endif
    }

    private var subtitleFont: Font {
        #if os(tvOS)
            return AppleTVTheme.cardSubtitleFont
        #else
            return .caption2
        #endif
    }
}

// MARK: - Seerr Card (unchanged — kept compatible)

public struct SeerrMediaCardView: View {
    let title: String
    let year: String?
    let posterURL: URL?
    let status: SeerrMediaStatus
    var cardWidth: CGFloat = 150

    public init(title: String, year: String?, posterURL: URL?, status: SeerrMediaStatus, cardWidth: CGFloat = 150) {
        self.title = title
        self.year = year
        self.posterURL = posterURL
        self.status = status
        self.cardWidth = cardWidth
    }

    #if os(tvOS)
        @FocusState private var isFocused: Bool
    #else
        @State private var isHovered: Bool = false
    #endif

    private var focused: Bool {
        #if os(tvOS)
            return isFocused
        #else
            return isHovered
        #endif
    }

    var cardHeight: CGFloat { cardWidth * 1.5 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            posterImage
                .scaleEffect(focused ? AppleTVTheme.focusScale : 1.0)
                .shadow(
                    color: focused ? .white.opacity(AppleTVTheme.focusGlowOpacity) : .clear,
                    radius: focused ? AppleTVTheme.focusGlowRadius : 0
                )
                .animation(.easeInOut(duration: AppleTVTheme.focusAnimDuration), value: focused)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(year ?? " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .frame(width: cardWidth)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled(true)
        #else
            .onHover { isHovered = $0 }
        #endif
    }

    private var posterImage: some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable()
                        .aspectRatio(2 / 3, contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.15), Color(white: 0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            Image(systemName: "film").foregroundStyle(.white.opacity(0.25)).font(.largeTitle)
                        }
                }
            }
            .posterCard(width: cardWidth, cornerRadius: 12)

            statusBadge
                .padding(8)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .available:
            Label("Available", systemImage: "checkmark")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.green)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        case .partiallyAvailable:
            Label("Partial", systemImage: "circle.lefthalf.filled")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.orange)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        case .pending, .processing:
            Label("Pending", systemImage: "clock")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.yellow)
                .foregroundStyle(.black)
                .clipShape(Capsule())
        default:
            EmptyView()
        }
    }
}
