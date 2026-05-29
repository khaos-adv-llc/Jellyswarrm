// MARK: - HomeView.swift

// Jellyswarrm — GPL v3 with App Store exception

import JellyswarrmCore
import SwiftUI

public struct HomeView: View {
    public init() {}

    @Environment(LibraryViewModel.self) private var libraryVM
    @Environment(AppState.self) private var appState

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppleTVTheme.shelfSpacing) {
                    if libraryVM.isLoading {
                        loadingSkeleton
                    } else {
                        // Hero featured item — full-bleed banner
                        if let featured = libraryVM.continueWatching.first ?? libraryVM.nextUp.first {
                            NavigationLink(value: featured) {
                                HeroHeaderView(
                                    item: featured,
                                    imageURL: heroBackdropURL(for: featured)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // Continue Watching
                        if !libraryVM.continueWatching.isEmpty {
                            shelf(
                                title: "Continue Watching",
                                items: libraryVM.continueWatching
                            )
                        }

                        // Next Up
                        if !libraryVM.nextUp.isEmpty {
                            shelf(
                                title: "Next Up",
                                items: libraryVM.nextUp
                            )
                        }

                        // Recently Added per section
                        ForEach(libraryVM.sections) { section in
                            let items = libraryVM.recentlyAdded[section.id] ?? []
                            if !items.isEmpty {
                                shelf(
                                    title: "Recently Added — \(section.name)",
                                    items: items
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 32)
            }
            .background(AppleTVTheme.background.ignoresSafeArea())
            .navigationTitle("Home")
            #if os(tvOS)
                // tvOS: the tab bar already supplies top-level navigation, so the
                // inline title pushes content down and hides the first shelf row.
                .toolbar(.hidden, for: .navigationBar)
            #endif
            .refreshable {
                await libraryVM.refresh()
            }
            .navigationDestination(for: MediaItem.self) { item in
                MediaDetailView(item: item)
                    .environment(libraryVM)
            }
        }
    }

    // MARK: - Components

    private func shelf(title: String, items: [MediaItem]) -> some View {
        ShelfRowView(title: title, items: items) { item in
            NavigationLink(value: item) {
                MediaCardView(
                    item: item,
                    imageURL: libraryVM.posterImageURL(for: item, maxWidth: Int(cardWidth * 2)),
                    cardWidth: cardWidth
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: AppleTVTheme.shelfSpacing) {
            // Placeholder hero
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.white.opacity(0.05))
                .aspectRatio(16.0 / 7.0, contentMode: .fit)
                .frame(maxWidth: .infinity)

            ForEach(0 ..< 3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    Text("Loading Shelf Title")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal, AppleTVTheme.shelfHorizontalPadding)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppleTVTheme.cardSpacing) {
                            ForEach(0 ..< 6, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.07))
                                    .frame(width: cardWidth, height: cardWidth * 1.5)
                            }
                        }
                        .padding(.horizontal, AppleTVTheme.shelfHorizontalPadding)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    /// For episodes, prefer the parent series backdrop so the hero doesn't show an episode still.
    private func heroBackdropURL(for item: MediaItem) -> URL? {
        if item.type == .episode, let seriesId = item.seriesId,
           let server = appState.currentServer
        {
            return JellyfinAPIClient.shared.imageURL(
                server: server, itemId: seriesId, imageType: .backdrop, tag: nil, maxWidth: 1280
            )
        }
        return libraryVM.imageURL(for: item, type: .backdrop, maxWidth: 1280)
    }

    // MARK: - Platform sizing

    private var cardWidth: CGFloat {
        #if os(tvOS)
            return 240
        #else
            return 140
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

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: heroHeight)
                        .clipped()
                default:
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(maxWidth: .infinity)
                        .frame(height: heroHeight)
                }
            }
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        AppleTVTheme.background.opacity(0.4),
                        AppleTVTheme.background,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Metadata — constrained to screen width so description can't overflow
            VStack(alignment: .leading, spacing: 8) {
                if let rating = item.communityRating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                Text(item.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .shadow(radius: 6)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(overviewLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, AppleTVTheme.shelfHorizontalPadding)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        #if os(tvOS)
            // Clamp the entire hero so text cannot escape and overlap shelves below.
            .frame(height: 360)
            .clipped()
        #endif
    }

    private var overviewLineLimit: Int {
        #if os(tvOS)
            return 3
        #else
            return 2
        #endif
    }

    private var heroHeight: CGFloat {
        #if os(tvOS)
            // ~47% of usable screen on a 1080p TV — leaves the first shelf row
            // visible below the hero without scrolling.
            return 360
        #elseif os(macOS)
            return 400
        #else
            // iPad regular = taller, iPhone compact = shorter
            if hSizeClass == .regular {
                return 380
            }
            return 320
        #endif
    }
}
