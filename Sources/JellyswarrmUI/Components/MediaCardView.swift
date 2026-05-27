// MARK: - MediaCardView.swift

// Jellyswarrm — GPL v3 with App Store exception
// Reusable poster card — handles focus engine on tvOS, tap on iOS/macOS

import JellyswarrmCore
import SwiftUI

public struct MediaCardView: View {
    let item: MediaItem
    let imageURL: URL?
    var showTitle: Bool = true
    var cardWidth: CGFloat = 150

    public init(item: MediaItem, imageURL: URL?, showTitle: Bool = true, cardWidth: CGFloat = 150) {
        self.item = item
        self.imageURL = imageURL
        self.showTitle = showTitle
        self.cardWidth = cardWidth
    }

    @State private var isFocused: Bool = false

    var cardHeight: CGFloat { cardWidth * 1.5 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            posterImage
            if showTitle {
                cardLabel
            }
        }
        .frame(width: cardWidth)
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .shadow(radius: isFocused ? 20 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        #endif
    }

    private var posterImage: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(2 / 3, contentMode: .fill)
                case .failure:
                    placeholderView
                case .empty:
                    placeholderView.overlay {
                        ProgressView().tint(.white)
                    }
                @unknown default:
                    placeholderView
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Progress bar overlay
            if let userData = item.userData, userData.hasProgress {
                progressOverlay(fraction: userData.normalizedProgress)
            }

            // Watched badge
            if item.userData?.played == true {
                watchedBadge
            }
        }
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
                        .fill(.white)
                        .frame(width: geo.size.width * fraction, height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var watchedBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.white, .black.opacity(0.6))
            .font(.caption)
            .padding(6)
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.2))
            .frame(width: cardWidth, height: cardHeight)
            .overlay {
                Image(systemName: "film")
                    .foregroundStyle(.white.opacity(0.3))
                    .font(.largeTitle)
            }
    }

    private var cardLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayTitle)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            if let year = item.productionYear {
                Text("\(year)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: cardWidth, alignment: .leading)
    }
}

// MARK: - Seerr Card

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

    @State private var isFocused: Bool = false

    var cardHeight: CGFloat { cardWidth * 1.5 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: posterURL) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                    default:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                Image(systemName: "film").foregroundStyle(.white.opacity(0.3)).font(.largeTitle)
                            }
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                statusBadge
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let year {
                    Text(year)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .frame(width: cardWidth)
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        #endif
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
