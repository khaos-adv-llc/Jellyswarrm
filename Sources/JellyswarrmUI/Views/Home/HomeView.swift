// MARK: - HomeView.swift

// Jellyswarrm — GPL v3 with App Store exception

import JellyswarrmCore
import SwiftUI

public struct HomeView: View {
    public init() {}

    @Environment(LibraryViewModel.self) private var libraryVM
    @Environment(AppState.self) private var appState

    @State private var selectedItem: MediaItem?
    @State private var showPlayer = false

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if libraryVM.isLoading {
                        loadingSkeleton
                    } else {
                        // Hero featured item
                        if let featured = libraryVM.continueWatching.first ?? libraryVM.nextUp.first {
                            HeroHeaderView(
                                item: featured,
                                imageURL: libraryVM.imageURL(for: featured, type: .backdrop, maxWidth: 1280)
                            )
                            .onTapGesture { selectedItem = featured; showPlayer = true }
                        }

                        // Continue Watching
                        if !libraryVM.continueWatching.isEmpty {
                            mediaRow(
                                title: "Continue Watching",
                                items: libraryVM.continueWatching,
                                cardWidth: cardWidth
                            )
                        }

                        // Next Up
                        if !libraryVM.nextUp.isEmpty {
                            mediaRow(
                                title: "Next Up",
                                items: libraryVM.nextUp,
                                cardWidth: cardWidth
                            )
                        }

                        // Recently Added per section
                        ForEach(libraryVM.sections) { section in
                            let items = libraryVM.recentlyAdded[section.id] ?? []
                            if !items.isEmpty {
                                mediaRow(
                                    title: "Recently Added — \(section.name)",
                                    items: items,
                                    cardWidth: cardWidth
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Home")
            .refreshable {
                await libraryVM.refresh()
            }
            .fullScreenCover(isPresented: $showPlayer) {
                if let item = selectedItem {
                    VideoPlayerView(item: item)
                }
            }
            .navigationDestination(for: MediaItem.self) { item in
                MediaDetailView(item: item)
            }
        }
    }

    // MARK: - Components

    private func mediaRow(title: String, items: [MediaItem], cardWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            MediaCardView(
                                item: item,
                                imageURL: libraryVM.imageURL(for: item, type: .primary, maxWidth: Int(cardWidth * 2)),
                                cardWidth: cardWidth
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(0 ..< 3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 160, height: 20)
                        .padding(.horizontal, horizontalPadding)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0 ..< 6, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: cardWidth, height: cardWidth * 1.5)
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - Platform sizing

    private var cardWidth: CGFloat {
        #if os(tvOS)
            return 240
        #else
            return 130
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            return 60
        #else
            return 16
        #endif
    }
}

// MARK: - Hero Header

public struct HeroHeaderView: View {
    let item: MediaItem
    let imageURL: URL?

    public init(item: MediaItem, imageURL: URL?) {
        self.item = item
        self.imageURL = imageURL
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                default:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(16 / 9, contentMode: .fill)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            .clipped()

            // Gradient overlay
            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: heroHeight)

            // Metadata
            VStack(alignment: .leading, spacing: 8) {
                if let rating = item.communityRating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                Text(item.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .lineLimit(2)

                if let overview = item.overview {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, heroPadding)
            .padding(.bottom, 20)
        }
    }

    private var heroHeight: CGFloat {
        #if os(tvOS)
            return 480
        #else
            return 280
        #endif
    }

    private var heroPadding: CGFloat {
        #if os(tvOS)
            return 60
        #else
            return 16
        #endif
    }
}
