// MARK: - MediaDetailView.swift

// Jellyswarrm — LGPL-2.1-or-later
// Full-bleed backdrop, frosted-glass info panel pinned to the bottom, and
// horizontal Play / Trailer / More buttons. On tvOS the Play button is the
// initial focus owner so the Siri Remote selects it on appear.

import JellyswarrmCore
import SwiftUI
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
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

    #if os(tvOS)
        enum DetailButton: Hashable { case play, restart, trailer, more, watched, favorite }
        @FocusState private var focusedButton: DetailButton?
    #endif

    var displayItem: MediaItem { detail ?? item }

    private var isPlayed: Bool {
        localUserData?.played ?? displayItem.isPlayed
    }

    private var playedPercentage: Double? {
        localUserData?.playedPercentage ?? displayItem.playedPercentage
    }

    /// Item whose artwork should fill the header. For an episode we use the
    /// parent series so the hero shows the series art, not the episode still.
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

    // MARK: - Body

    public var body: some View {
        #if os(tvOS)
            tvBody
                .task { await loadAll() }
                .onChange(of: showPlayer) { _, newValue in
                    guard newValue else { return }
                    Task { @MainActor in
                        let vm = PlayerViewModel(appState: appState)
                        await vm.loadPlayback(for: displayItem, startFromBeginning: startFromBeginning)
                        vm.launchTVOSPlayer()
                        showPlayer = false
                    }
                }
        #else
            nonTVBody
        #endif
    }

    // MARK: - tvOS layout (spec)

    #if os(tvOS)
        private var tvBody: some View {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // First screen — full-bleed backdrop + frosted info panel
                    ZStack {
                        backdropLayer
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            infoPanelTV
                        }
                    }
                    .frame(
                        width: UIScreen.main.bounds.width,
                        height: UIScreen.main.bounds.height
                    )

                    // Below-the-fold series content
                    if displayItem.type == .series {
                        seriesContent
                    }
                }
            }
            .ignoresSafeArea()
            .background(AppleTVTheme.background)
            .focusSection()
        }

        private var backdropLayer: some View {
            ZStack {
                AsyncImage(url: backdropURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        AppleTVTheme.background
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                // Dark gradient over the backdrop for legibility
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.1), location: 0),
                        .init(color: .black.opacity(0.55), location: 0.45),
                        .init(color: .black.opacity(0.90), location: 0.85),
                        .init(color: AppleTVTheme.background, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }

        private var infoPanelTV: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text(displayItem.name)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)

                metaRow

                if let overview = displayItem.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 24))
                        .foregroundStyle(AppleTVTheme.labelSecondary)
                        .lineLimit(4)
                        .frame(maxWidth: 1100, alignment: .leading)
                }

                actionButtonsTV
                    .padding(.top, 8)
            }
            .padding(.horizontal, AppleTVTheme.safeInset)
            .padding(.top, 40)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, AppleTVTheme.background.opacity(0.85), AppleTVTheme.background],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .onAppear {
                // Apple TV app convention — Play is the initial focus owner.
                focusedButton = .play
            }
        }

        private var metaRow: some View {
            HStack(spacing: 16) {
                if let year = displayItem.productionYear {
                    Text(String(year)).foregroundStyle(AppleTVTheme.labelSecondary)
                }
                if let rating = displayItem.officialRating {
                    Text(rating)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(AppleTVTheme.labelSecondary, lineWidth: 1)
                        )
                        .foregroundStyle(AppleTVTheme.labelSecondary)
                }
                if let runtime = displayItem.runtimeTicks {
                    Text(runtime.ticksToDurationString)
                        .foregroundStyle(AppleTVTheme.labelSecondary)
                }
                if let rating = displayItem.communityRating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .font(.system(size: 22))
        }

        private var actionButtonsTV: some View {
            HStack(spacing: 20) {
                if displayItem.type.isPlayable {
                    detailButton(
                        icon: playedPercentage.map { $0 > 0 } ?? false ? "play.fill" : "play.fill",
                        label: resumeLabel,
                        primary: true
                    ) {
                        startFromBeginning = false
                        showPlayer = true
                    }
                    .focused($focusedButton, equals: .play)
                }

                if displayItem.type.isPlayable, let pct = playedPercentage, pct > 0 {
                    detailButton(icon: "arrow.counterclockwise", label: "Restart", primary: false) {
                        startFromBeginning = true
                        showPlayer = true
                    }
                    .focused($focusedButton, equals: .restart)
                }

                detailButton(
                    icon: isPlayed ? "checkmark.circle.fill" : "checkmark.circle",
                    label: isPlayed ? "Watched" : "Mark Watched",
                    primary: false
                ) {
                    Task { await toggleWatched() }
                }
                .focused($focusedButton, equals: .watched)

                detailButton(
                    icon: displayItem.userData?.isFavorite == true ? "heart.fill" : "heart",
                    label: "Favorite",
                    primary: false
                ) {
                    Task { await toggleFavorite() }
                }
                .focused($focusedButton, equals: .favorite)
            }
        }

        @ViewBuilder
        private func detailButton(
            icon: String,
            label: String,
            primary: Bool,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                    Text(label)
                        .font(.system(size: 22, weight: .semibold))
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(primary ? Color.white : Color.white.opacity(0.15))
                .foregroundStyle(primary ? Color.black : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            // Default focus glow on buttons is correct — buttons are the rare
            // place we WANT the system focus effect.
        }

        private var resumeLabel: String {
            if displayItem.userData?.hasProgress == true {
                return "Resume"
            }
            return "Play"
        }

        @ViewBuilder
        private var seriesContent: some View {
            VStack(alignment: .leading, spacing: 24) {
                seasonsSection
                episodesSection
            }
            .padding(.horizontal, AppleTVTheme.safeInset)
            .padding(.top, 40)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    #endif

    // MARK: - iOS / macOS layout

    #if !os(tvOS)
        private var nonTVBody: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
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
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await loadAll() }
            #if os(macOS)
            .onChange(of: showPlayer) { _, newValue in
                if newValue {
                    presentMacPlayer()
                }
            }
            #else
            .onChange(of: showPlayer) { _, newValue in
                guard newValue else { return }
                PlayerPresenter.presentPlayer(
                    item: displayItem,
                    startFromBeginning: startFromBeginning,
                    appState: appState,
                    onDismissed: { showPlayer = false }
                )
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

        private var backdropSection: some View {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { geo in
                    AsyncImage(url: backdropURL) { phase in
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
                    .buttonStyle(.plain)
                }

                if displayItem.type.isPlayable, let percent = playedPercentage, percent > 0 {
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
                    Task { await toggleFavorite() }
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
    #endif

    // MARK: - Shared content padding

    private var contentPadding: CGFloat {
        #if os(tvOS)
            return AppleTVTheme.safeInset
        #elseif os(macOS)
            return 32
        #else
            return 20
        #endif
    }

    // MARK: - Backdrop URL (shared)

    private var backdropURL: URL? {
        if let backdrop = libraryVM.imageURL(for: headerItem, type: .backdrop, maxWidth: 1920) {
            return backdrop
        }
        return libraryVM.imageURL(for: headerItem, type: .primary, maxWidth: 1920)
    }

    // MARK: - Loading

    private func loadAll() async {
        detail = try? await libraryVM.getDetail(for: item.id)
        isLoading = false
        if displayItem.type == .series {
            await loadSeasons()
        } else if displayItem.type == .episode, let seriesId = displayItem.seriesId {
            seriesDetail = try? await libraryVM.getDetail(for: seriesId)
        }
    }

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

    #if os(macOS)
    private func presentMacPlayer() {
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

    // MARK: - Toggles

    private func toggleWatched() async {
        let target = !isPlayed
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
            localUserData = displayItem.userData
        }
    }

    private func toggleFavorite() async {
        // Optimistic toggle, then call API if available.
        try? await libraryVM.toggleFavorite(displayItem)
    }

    // MARK: - Seasons / Episodes (shared)

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seasons")
                .font(seasonsHeaderFont)
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
        #if os(tvOS)
            .focusSection()
        #endif
    }

    private var seasonsHeaderFont: Font {
        #if os(tvOS)
            return .system(size: 28, weight: .bold)
        #else
            return .title3
        #endif
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episodes")
                .font(seasonsHeaderFont)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            if isLoadingEpisodes {
                ProgressView().tint(.white)
            } else if episodes.isEmpty {
                Text("No episodes available")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                #if os(tvOS)
                    // tvOS: horizontal episode row with focusable cards.
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: AppleTVTheme.cardSpacing) {
                            ForEach(episodes) { episode in
                                Button {
                                    TVNavigationCoordinator.shared.push(
                                        MediaDetailView(item: episode)
                                            .environment(libraryVM)
                                            .environment(appState)
                                    )
                                } label: {
                                    MediaCardView(
                                        item: episode,
                                        imageURL: libraryVM.imageURL(for: episode, type: .primary, maxWidth: 880),
                                        cardWidth: AppleTVTheme.wideCardWidthTVOS,
                                        cardHeight: AppleTVTheme.wideCardHeightTVOS
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    .focusSection()
                #else
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(episodes) { episode in
                            NavigationLink {
                                MediaDetailView(item: episode)
                                    .environment(libraryVM)
                                    .environment(appState)
                            } label: {
                                episodeRow(episode)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                #endif
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
}
