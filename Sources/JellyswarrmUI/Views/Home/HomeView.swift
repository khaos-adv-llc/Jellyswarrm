// MARK: - HomeView.swift (Watch Now)

// Jellyswarrm — LGPL-2.1-or-later
// "Watch Now" tab — Apple TV app fidelity. Full-bleed hero, auto-rotating
// featured items, gradient overlay, then horizontal shelf rows.

import JellyswarrmCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct HomeView: View {
    public init() {}

    @Environment(LibraryViewModel.self) private var libraryVM
    @Environment(AppState.self) private var appState

    public var body: some View {
        #if os(tvOS)
            // tvOS uses TVNavigationCoordinator instead of NavigationStack to
            // avoid the ghost-title / double-dismiss bugs that NavigationStack
            // produces in the UIKit-hosted tab bar shell.
            content
        #else
            NavigationStack {
                content
                    .navigationTitle("Watch Now")
                    .navigationDestination(for: MediaItem.self) { item in
                        MediaDetailView(item: item)
                            .environment(libraryVM)
                    }
            }
        #endif
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if libraryVM.isLoading, libraryVM.continueWatching.isEmpty, libraryVM.nextUp.isEmpty {
                    loadingSkeleton
                } else {
                    // Hero — auto-rotating featured items
                    if !heroItems.isEmpty {
                        HeroSectionView(
                            items: heroItems,
                            backdropURL: { item in heroBackdropURL(for: item) }
                        )
                    }

                    // Shelf rows
                    VStack(alignment: .leading, spacing: AppleTVTheme.shelfSpacing) {
                        if !libraryVM.continueWatching.isEmpty {
                            shelf(
                                title: "Continue Watching",
                                items: libraryVM.continueWatching,
                                style: .wide
                            )
                        }
                        if !libraryVM.nextUp.isEmpty {
                            shelf(
                                title: "Next Up",
                                items: libraryVM.nextUp,
                                style: .wide
                            )
                        }
                        ForEach(libraryVM.sections) { section in
                            let items = libraryVM.recentlyAdded[section.id] ?? []
                            if !items.isEmpty {
                                shelf(
                                    title: "Recently Added — \(section.name)",
                                    items: items,
                                    style: .portrait
                                )
                            }
                        }
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 80)
                }
            }
        }
        .background(AppleTVTheme.background.ignoresSafeArea())
        #if os(tvOS)
            // Required for diagonal focus navigation across hero and shelves.
            .focusSection()
        #endif
        .refreshable {
            await libraryVM.refresh()
        }
    }

    // MARK: - Featured items for hero

    private var heroItems: [MediaItem] {
        // Prefer Continue Watching first; fall back to Next Up; finally fall
        // back to first non-empty Recently Added section.
        var pool: [MediaItem] = []
        pool.append(contentsOf: libraryVM.continueWatching.prefix(3))
        pool.append(contentsOf: libraryVM.nextUp.prefix(3))
        if pool.count < 3 {
            for section in libraryVM.sections {
                let items = libraryVM.recentlyAdded[section.id] ?? []
                pool.append(contentsOf: items.prefix(3))
                if pool.count >= 6 { break }
            }
        }
        // Dedupe by id, keep first 6
        var seen = Set<String>()
        return pool.filter { seen.insert($0.id).inserted }.prefix(6).map { $0 }
    }

    // MARK: - Shelf builder (uses existing ShelfRowView API)

    @ViewBuilder
    private func shelf(title: String, items: [MediaItem], style: CardStyle) -> some View {
        ShelfRowView(title: title, items: items) { item in
            cardLink(for: item, style: style)
        }
    }

    @ViewBuilder
    private func cardLink(for item: MediaItem, style: CardStyle) -> some View {
        #if os(tvOS)
            Button {
                TVNavigationCoordinator.shared.push(
                    MediaDetailView(item: item)
                        .environment(libraryVM)
                        .environment(appState)
                )
            } label: {
                MediaCardView(
                    item: item,
                    imageURL: posterURL(for: item, style: style),
                    cardWidth: style.cardWidth,
                    cardHeight: style.cardHeight
                )
            }
            .buttonStyle(.plain)
        #else
            NavigationLink(value: item) {
                MediaCardView(
                    item: item,
                    imageURL: posterURL(for: item, style: style),
                    cardWidth: style.cardWidth,
                    cardHeight: style.cardHeight
                )
            }
            .buttonStyle(.plain)
        #endif
    }

    private func posterURL(for item: MediaItem, style: CardStyle) -> URL? {
        switch style {
        case .portrait:
            return libraryVM.posterImageURL(for: item, maxWidth: 500)
        case .wide:
            return libraryVM.imageURL(for: item, type: .thumb, maxWidth: 880)
                ?? libraryVM.imageURL(for: item, type: .backdrop, maxWidth: 880)
                ?? libraryVM.posterImageURL(for: item, maxWidth: 500)
        }
    }

    // MARK: - Hero backdrop

    /// For episodes, prefer the parent series backdrop so the hero doesn't
    /// show an episode still.
    private func heroBackdropURL(for item: MediaItem) -> URL? {
        if item.type == .episode, let seriesId = item.seriesId,
           let server = appState.currentServer
        {
            return JellyfinAPIClient.shared.imageURL(
                server: server, itemId: seriesId, imageType: .backdrop, tag: nil, maxWidth: 1920
            )
        }
        return libraryVM.imageURL(for: item, type: .backdrop, maxWidth: 1920)
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: AppleTVTheme.shelfSpacing) {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.white.opacity(0.05))
                .frame(height: skeletonHeroHeight)

            ForEach(0 ..< 3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    Text("Loading Shelf Title")
                        .font(AppleTVTheme.sectionHeaderFont)
                        .padding(.horizontal, AppleTVTheme.shelfHorizontalPadding)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppleTVTheme.cardSpacing) {
                            ForEach(0 ..< 6, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.07))
                                    .frame(width: 200, height: 300)
                            }
                        }
                        .padding(.horizontal, AppleTVTheme.shelfHorizontalPadding)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private var skeletonHeroHeight: CGFloat {
        #if os(tvOS)
            return UIScreen.main.bounds.height * AppleTVTheme.heroHeightRatio
        #elseif os(macOS)
            return 400
        #else
            return 260
        #endif
    }
}

// MARK: - Card style (used by HomeView shelf rows)

public enum CardStyle: Sendable, Hashable {
    case portrait, wide

    public var cardWidth: CGFloat {
        #if os(tvOS)
            switch self {
            case .portrait: return AppleTVTheme.cardWidthTVOS
            case .wide: return AppleTVTheme.wideCardWidthTVOS
            }
        #else
            switch self {
            case .portrait: return AppleTVTheme.cardWidthIOS
            case .wide: return 200
            }
        #endif
    }

    public var cardHeight: CGFloat {
        #if os(tvOS)
            switch self {
            case .portrait: return AppleTVTheme.cardHeightTVOS
            case .wide: return AppleTVTheme.wideCardHeightTVOS
            }
        #else
            switch self {
            case .portrait: return AppleTVTheme.cardHeightIOS
            case .wide: return 112
            }
        #endif
    }

    public var cornerRadius: CGFloat { 12 }
}

// MARK: - Hero Section

/// Full-bleed hero — ~42% of screen height on tvOS. NOT focusable, NOT a
/// button: display only, auto-rotates every 8s. The first focusable element
/// below is the first shelf card.
public struct HeroSectionView: View {
    let items: [MediaItem]
    let backdropURL: (MediaItem) -> URL?

    @State private var currentIndex: Int = 0
    @State private var timer: Timer?

    public init(items: [MediaItem], backdropURL: @escaping (MediaItem) -> URL?) {
        self.items = items
        self.backdropURL = backdropURL
    }

    private var current: MediaItem { items[min(currentIndex, items.count - 1)] }

    private var heroHeight: CGFloat {
        #if os(tvOS)
            return UIScreen.main.bounds.height * AppleTVTheme.heroHeightRatio
        #elseif os(macOS)
            return 420
        #else
            return 260
        #endif
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image — fills full width at fixed hero height
            GeometryReader { geo in
                AsyncImage(url: backdropURL(current)) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: heroHeight)
                            .clipped()
                    default:
                        Rectangle().fill(AppleTVTheme.cardBackground)
                            .frame(width: geo.size.width, height: heroHeight)
                    }
                }
            }
            .frame(height: heroHeight)

            // Gradient overlay — transparent top → near-opaque background at bottom
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.35),
                    .init(color: AppleTVTheme.background.opacity(0.6), location: 0.65),
                    .init(color: AppleTVTheme.background.opacity(0.95), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: heroHeight)
            .allowsHitTesting(false)

            // Text overlay
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    if let rating = current.communityRating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 22, weight: .semibold))
                    }
                    if let year = current.productionYear {
                        Text(String(year))
                            .foregroundStyle(AppleTVTheme.labelSecondary)
                            .font(.system(size: 22, weight: .regular))
                    }
                }

                Text(current.name)
                    .font(AppleTVTheme.heroTitleFont)
                    .foregroundStyle(AppleTVTheme.labelPrimary)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                    .lineLimit(2)

                if let overview = current.overview, !overview.isEmpty {
                    Text(overview)
                        .font(AppleTVTheme.heroSubtitleFont)
                        .foregroundStyle(AppleTVTheme.labelSecondary)
                        .lineLimit(3)
                        .frame(maxWidth: 800, alignment: .leading)
                }

                // Dot indicator
                if items.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0 ..< min(items.count, 6), id: \.self) { i in
                            Circle()
                                .fill(i == currentIndex ? Color.white : Color.white.opacity(0.35))
                                .frame(
                                    width: i == currentIndex ? 8 : 6,
                                    height: i == currentIndex ? 8 : 6
                                )
                                .animation(.easeInOut(duration: 0.2), value: currentIndex)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, AppleTVTheme.safeInset)
            .padding(.bottom, 36)
            .allowsHitTesting(false)
        }
        .frame(height: heroHeight)
        .clipped()  // Prevent text from escaping the hero region
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(current.name))
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    private func startTimer() {
        stopTimer()
        guard items.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.6)) {
                    currentIndex = (currentIndex + 1) % min(items.count, 6)
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

