// MARK: - MediaDetailView.swift

// Jellyswarrm — LGPL-2.1-or-later

import JellyswarrmCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct MediaDetailView: View {
    let item: MediaItem

    public init(item: MediaItem) {
        self.item = item
    }
    @Environment(LibraryViewModel.self) private var libraryVM
    @Environment(AppState.self) private var appState
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

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
    #if os(macOS)
    @State private var playerWindow: PlayerWindowController?
    #endif

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

    private var useTwoColumnLayout: Bool {
        #if os(macOS)
            return true
        #elseif os(iOS)
            return hSizeClass == .regular
        #else
            return false
        #endif
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Full-bleed backdrop
                backdropSection

                if useTwoColumnLayout, displayItem.type == .series {
                    twoColumnContent
                } else {
                    singleColumnContent
                }
            }
        }
        .background(AppleTVTheme.background.ignoresSafeArea())
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
        .onChange(of: showPlayer) { _, newValue in
            if newValue {
                presentMacPlayer()
            }
        }
        #elseif os(iOS)
        // Direct UIKit presentation of AVPlayerViewController (or VLC hosting
        // controller) — no SwiftUI .fullScreenCover layer. This eliminates the
        // "tap Done twice" bug: tapping Done dismisses the only modal layer,
        // returning straight to the detail view.
        .onChange(of: showPlayer) { _, newValue in
            guard newValue else { return }
            PlayerPresenter.presentPlayer(
                item: displayItem,
                startFromBeginning: startFromBeginning,
                appState: appState,
                onDismissed: { showPlayer = false }
            )
        }
        #else
        .fullScreenCover(isPresented: $showPlayer) {
            // tvOS still uses .fullScreenCover — TVPlayerRepresentable is
            // designed to be the top-level view returned from the cover so
            // UIKit hands it the full screen and routes Siri Remote focus.
            //
            // .fullScreenCover presents in a separate window scene on tvOS,
            // which does not inherit the parent's @Environment values. Pass
            // appState/libraryVM through explicitly so VideoPlayerView and
            // its PlayerViewModel can resolve the current server.
            VideoPlayerView(item: displayItem, startFromBeginning: startFromBeginning)
                .id(displayItem.id)
                .environment(appState)
                .environment(libraryVM)
        }
        #endif
    }

    private var singleColumnContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            infoPanel
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
        .padding(.horizontal, contentPadding)
        .padding(.top, 20)
        .padding(.bottom, 32)
    }

    private var twoColumnContent: some View {
        HStack(alignment: .top, spacing: 32) {
            // Left: metadata, actions, overview, cast
            VStack(alignment: .leading, spacing: 24) {
                infoPanel
                actionButtons
                if let overview = displayItem.overview, !overview.isEmpty {
                    overviewSection(overview)
                }
                if let people = displayItem.people, !people.isEmpty {
                    castSection(people)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)

            // Right: seasons & episodes
            VStack(alignment: .leading, spacing: 16) {
                seasonsSection
                episodesSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, contentPadding)
        .padding(.top, 20)
        .padding(.bottom, 32)
    }

    private var contentPadding: CGFloat {
        #if os(tvOS)
            return 60
        #elseif os(macOS)
            return 32
        #else
            return 20
        #endif
    }

    #if os(macOS)
    private func presentMacPlayer() {
        // Reuse an existing controller if one is mid-teardown so a rapid
        // re-tap can't leak windows.
        playerWindow?.window?.close()
        let controller = PlayerWindowController(
            item: displayItem,
            startFromBeginning: startFromBeginning,
            appState: appState
        )
        controller.onClosed = {
            showPlayer = false
            playerWindow = nil
        }
        playerWindow = controller
        controller.present()
    }
    #endif

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
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            if seasons.isEmpty {
                Text(isLoading ? "Loading..." : "No seasons available")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
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
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(selectedSeasonId == season.id
                                        ? Color.accentColor
                                        : Color.white.opacity(0.12))
                                    .foregroundStyle(selectedSeasonId == season.id ? Color.white : Color.white.opacity(0.9))
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
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            if isLoadingEpisodes {
                ProgressView().tint(.white)
            } else if episodes.isEmpty {
                Text("No episodes available")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(episodes) { episode in
                        NavigationLink {
                            MediaDetailView(item: episode)
                                .environment(libraryVM)
                                .environment(appState)
                        } label: {
                            episodeRow(episode)
                        }
                        #if os(tvOS)
                            // .plain episode rows are invisible to the focus
                            // engine; .card scales the row on focus.
                            .buttonStyle(.card)
                        #else
                            .buttonStyle(.plain)
                        #endif
                    }
                }
            }
        }
    }

    private func episodeRow(_ episode: MediaItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: libraryVM.imageURL(for: episode, type: .primary, maxWidth: 320)) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().aspectRatio(16 / 9, contentMode: .fill)
                    default:
                        RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08))
                    }
                }
                .frame(width: 160, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if episode.isPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .padding(6)
                        .accessibilityLabel("Watched")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Backdrop

    private var backdropSection: some View {
        ZStack(alignment: .bottomLeading) {
            #if os(tvOS)
                // GeometryReader inside a ScrollView is unreliable on tvOS
                // (zero-height races during layout). Use a fixed height.
                AsyncImage(url: headerImageURL) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 540)
                            .clipped()
                    default:
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(maxWidth: .infinity)
                            .frame(height: 540)
                    }
                }
            #else
                GeometryReader { geo in
                    AsyncImage(url: headerImageURL) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.width * 9.0 / 16.0)
                                .clipped()
                        default:
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(width: geo.size.width, height: geo.size.width * 9.0 / 16.0)
                        }
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
            #endif

            LinearGradient(
                colors: [
                    .clear,
                    AppleTVTheme.background.opacity(0.4),
                    AppleTVTheme.background,
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
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
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 4)
                }
            }
            .padding(.horizontal, contentPadding)
            .padding(.bottom, 20)
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

    // MARK: - Info Panel (frosted glass)

    private var infoPanel: some View {
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
                metaBadge(String(format: "%.1f", community), icon: "star.fill", tint: .yellow)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func metaBadge(_ text: String, icon: String, tint: Color = .white) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(tint == .white ? .white.opacity(0.9) : tint)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if displayItem.type.isPlayable {
                Button {
                    startFromBeginning = false
                    showPlayer = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: displayItem.userData?.hasProgress == true ? "play.circle.fill" : "play.fill")
                            .font(.title3)
                        Text(displayItem.userData?.hasProgress == true ? "Resume" : "Play")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
                }
                #if os(tvOS)
                    // .card gives the play button visible focus scaling; on
                    // tvOS .plain leaves it unhighlighted and unusable with
                    // the Siri Remote.
                    .buttonStyle(.card)
                #else
                    .buttonStyle(.plain)
                #endif
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
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restart")
            }

            // Watched toggle
            Button {
                Task { await toggleWatched() }
            } label: {
                Image(systemName: isPlayed ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(isPlayed ? .green : .white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlayed ? "Mark Unwatched" : "Mark Watched")

            Button {
                // Favorite toggle — implement with libraryVM.toggleFavorite
            } label: {
                Image(systemName: displayItem.userData?.isFavorite == true ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(displayItem.userData?.isFavorite == true ? .pink : .white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
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
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            ExpandableText(text, font: .callout)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Cast

    private func castSection(_ people: [PersonInfo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast & Crew")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(people.prefix(12)) { person in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 70, height: 70)
                                .overlay {
                                    if let server = appState.currentServer,
                                       let tag = person.primaryImageTag
                                    {
                                        AsyncImage(url: JellyfinAPIClient.shared.imageURL(
                                            server: server,
                                            itemId: person.id,
                                            imageType: .primary,
                                            tag: tag,
                                            maxWidth: 140
                                        )) { phase in
                                            if case let .success(image) = phase {
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            } else {
                                                Image(systemName: "person.fill")
                                                    .foregroundStyle(.white.opacity(0.5))
                                            }
                                        }
                                        .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.fill")
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }

                            Text(person.name)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 80)

                            if let role = person.role {
                                Text(role)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                                    .frame(width: 80)
                            }
                        }
                    }
                }
            }
        }
    }
}
