// MARK: - MediaDetailView.swift

// Jellyswarrm — GPL v3 with App Store exception

import JellyswarrmCore
import SwiftUI

public struct MediaDetailView: View {
    let item: MediaItem

    public init(item: MediaItem) {
        self.item = item
    }
    @Environment(LibraryViewModel.self) private var libraryVM
    @Environment(AppState.self) private var appState

    @State private var detail: MediaItem?
    @State private var seriesDetail: MediaItem?
    @State private var isLoading = true
    @State private var showPlayer = false
    @State private var startFromBeginning = false
    @State private var localUserData: UserData?
    @State private var seasons: [MediaItem] = []
    @State private var selectedSeasonId: String?
    @State private var episodes: [MediaItem] = []
    @State private var isLoadingEpisodes = false

    var displayItem: MediaItem { detail ?? item }

    /// True when the user has marked this item watched (locally or from server)
    private var isPlayed: Bool {
        localUserData?.played ?? displayItem.isPlayed
    }

    /// 0–100 playback progress, drawn from local optimistic state when available
    private var playedPercentage: Double? {
        localUserData?.playedPercentage ?? displayItem.playedPercentage
    }

    /// Item whose artwork should fill the header. For a series this is the
    /// series itself; for an episode we use the parent series so the hero
    /// shows series-level art instead of an episode still.
    var headerItem: MediaItem {
        if displayItem.type == .episode, let series = seriesDetail {
            return series
        }
        return displayItem
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Backdrop
                backdropSection

                // Main content
                VStack(alignment: .leading, spacing: 20) {
                    metadataSection
                    actionButtons
                    if let overview = displayItem.overview, !overview.isEmpty {
                        overviewSection(overview)
                    }
                    if displayItem.type == .series {
                        seasonsSection
                        episodesSection
                    }
                    if let people = displayItem.people, !people.isEmpty {
                        castSection(people)
                    }
                }
                .padding()
            }
        }
        .ignoresSafeArea(edges: .top)
        #if !os(tvOS) && !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            detail = try? await libraryVM.getDetail(for: item.id)
            isLoading = false
            if displayItem.type == .series {
                await loadSeasons()
            } else if displayItem.type == .episode, let seriesId = displayItem.seriesId {
                seriesDetail = try? await libraryVM.getDetail(for: seriesId)
            }
        }
        #if os(macOS)
        .sheet(isPresented: $showPlayer) {
            VideoPlayerView(item: displayItem, startFromBeginning: startFromBeginning)
                .frame(minWidth: 800, minHeight: 450)
        }
        #else
        .fullScreenCover(isPresented: $showPlayer) {
            VideoPlayerView(item: displayItem, startFromBeginning: startFromBeginning)
        }
        #endif
    }

    // MARK: - Series Loading

    private func loadSeasons() async {
        let fetched = (try? await libraryVM.getSeasons(for: displayItem.id)) ?? []
        seasons = fetched
        if let first = fetched.first {
            selectedSeasonId = first.id
            await loadEpisodes(for: first.id)
        }
    }

    private func loadEpisodes(for seasonId: String) async {
        isLoadingEpisodes = true
        episodes = (try? await libraryVM.getEpisodes(for: displayItem.id, seasonId: seasonId)) ?? []
        isLoadingEpisodes = false
    }

    // MARK: - Seasons

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seasons")
                .font(.headline)
            if seasons.isEmpty {
                Text(isLoading ? "Loading..." : "No seasons available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(seasons) { season in
                            Button {
                                selectedSeasonId = season.id
                                Task { await loadEpisodes(for: season.id) }
                            } label: {
                                Text(season.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selectedSeasonId == season.id ? Color.accentColor : Color.gray.opacity(0.15))
                                    .foregroundStyle(selectedSeasonId == season.id ? Color.white : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Episodes

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episodes")
                .font(.headline)
            if isLoadingEpisodes {
                ProgressView()
            } else if episodes.isEmpty {
                Text("No episodes available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(episodes) { episode in
                        NavigationLink(value: episode) {
                            episodeRow(episode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func episodeRow(_ episode: MediaItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: libraryVM.imageURL(for: episode, type: .primary, maxWidth: 320)) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().aspectRatio(16 / 9, contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2))
                }
            }
            .frame(width: 140, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(episode.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    if episode.isPlayed {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel("Watched")
                    }
                }
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Backdrop

    private var backdropSection: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: headerImageURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                default:
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 280)

            VStack(alignment: .leading, spacing: 4) {
                // Always show the item's own name — never swap to seriesName so the title
                // doesn't flicker when the full item fetch completes.
                Text(displayItem.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(radius: 6)
                if displayItem.type == .episode, let subtitle = episodeSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var episodeSubtitle: String? {
        let s = displayItem.parentIndexNumber.map { "S\($0)" } ?? ""
        let e = displayItem.indexNumber.map { "E\($0)" } ?? ""
        let prefix = "\(s)\(e)"
        let series = displayItem.seriesName ?? ""
        switch (prefix.isEmpty, series.isEmpty) {
        case (true, true): return nil
        case (false, true): return prefix
        case (true, false): return series
        case (false, false): return "\(prefix) · \(series)"
        }
    }

    private var headerImageURL: URL? {
        if let backdrop = libraryVM.imageURL(for: headerItem, type: .backdrop, maxWidth: 1280) {
            return backdrop
        }
        return libraryVM.imageURL(for: headerItem, type: .primary, maxWidth: 1280)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        HStack(spacing: 12) {
            if let year = displayItem.productionYear {
                metaBadge(String(year), icon: "calendar")
            }
            if let rating = displayItem.officialRating {
                metaBadge(rating, icon: "checkmark.seal")
            }
            if let runtime = displayItem.runtimeTicks {
                metaBadge(runtime.ticksToDurationString, icon: "clock")
            }
            if let community = displayItem.communityRating {
                metaBadge(String(format: "%.1f", community), icon: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.caption)
    }

    private func metaBadge(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if displayItem.type.isPlayable {
                Button {
                    startFromBeginning = false
                    showPlayer = true
                } label: {
                    HStack {
                        Image(systemName: displayItem.userData?.hasProgress == true ? "play.circle" : "play.fill")
                        Text(displayItem.userData?.hasProgress == true ? "Resume" : "Play")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            // Restart — only when there's existing playback progress
            if displayItem.type.isPlayable,
               let percent = playedPercentage, percent > 0
            {
                Button {
                    startFromBeginning = true
                    showPlayer = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restart")
            }

            // Watched toggle
            Button {
                Task { await toggleWatched() }
            } label: {
                Image(systemName: isPlayed ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(isPlayed ? .green : .primary)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlayed ? "Mark Unwatched" : "Mark Watched")

            Button {
                // Favorite toggle — implement with libraryVM.toggleFavorite
            } label: {
                Image(systemName: displayItem.userData?.isFavorite == true ? "heart.fill" : "heart")
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleWatched() async {
        let target = !isPlayed
        // Optimistic local update so the button flips instantly
        localUserData = UserData(
            playbackPositionTicks: localUserData?.playbackPositionTicks ?? displayItem.userData?.playbackPositionTicks ?? 0,
            playCount: localUserData?.playCount ?? displayItem.userData?.playCount ?? 0,
            isFavorite: localUserData?.isFavorite ?? displayItem.userData?.isFavorite ?? false,
            played: target,
            key: localUserData?.key ?? displayItem.userData?.key ?? "",
            lastPlayedDate: localUserData?.lastPlayedDate ?? displayItem.userData?.lastPlayedDate,
            playedPercentage: target ? 100 : 0,
            unplayedItemCount: localUserData?.unplayedItemCount ?? displayItem.userData?.unplayedItemCount
        )
        do {
            localUserData = try await libraryVM.setPlayed(target, itemId: displayItem.id)
        } catch {
            // Revert optimistic flip on failure
            localUserData = displayItem.userData
        }
    }

    // MARK: - Overview

    private func overviewSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
            ExpandableText(text, font: .callout)
        }
    }

    // MARK: - Cast

    private func castSection(_ people: [PersonInfo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast & Crew")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(people.prefix(10)) { person in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 60, height: 60)
                                .overlay {
                                    if let server = appState.currentServer,
                                       let tag = person.primaryImageTag
                                    {
                                        AsyncImage(url: JellyfinAPIClient.shared.imageURL(
                                            server: server,
                                            itemId: person.id,
                                            imageType: .primary,
                                            tag: tag,
                                            maxWidth: 120
                                        )) { phase in
                                            if case let .success(image) = phase {
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            } else {
                                                Image(systemName: "person.fill")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                            Text(person.name)
                                .font(.caption2)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 70)

                            if let role = person.role {
                                Text(role)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 70)
                            }
                        }
                    }
                }
            }
        }
    }
}
