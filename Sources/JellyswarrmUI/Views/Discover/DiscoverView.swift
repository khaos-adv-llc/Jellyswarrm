// MARK: - DiscoverView.swift

// Jellyswarrm — GPL v3 with App Store exception
// Jellyseerr-powered discover section: browse trending, upcoming, by genre.
// Items show availability status and request buttons directly.

import JellyswarrmCore
import SwiftUI

public struct DiscoverView: View {
    public init() {}

    @Environment(DiscoverViewModel.self) private var discoverVM
    @Environment(AppState.self) private var appState

    @State private var selectedResult: DiscoverDetailTarget?

    enum DiscoverDetailTarget: Identifiable {
        case movie(SeerrMovieResult)
        case tv(SeerrTvResult)
        var id: Int {
            switch self { case let .movie(m): return m.id; case let .tv(t): return t.id }
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if !appState.hasSeerrConfigured {
                    noSeerrView
                } else if discoverVM.isLoading, discoverVM.trendingItems.isEmpty {
                    ProgressView("Loading Discover...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    discoverContent
                }
            }
            .navigationTitle("Discover")
            .sheet(item: $selectedResult) { target in
                switch target {
                case let .movie(m): SeerrDetailView(movie: m)
                case let .tv(t): SeerrDetailView(tv: t)
                }
            }
        }
    }

    // MARK: - Main Content

    private var discoverContent: some View {
        @Bindable var discoverVM = discoverVM
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                // Tab picker
                Picker("", selection: $discoverVM.activeTab) {
                    ForEach(DiscoverMediaTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                #if !os(tvOS)
                    .pickerStyle(.segmented)
                #endif
                .padding(.horizontal, hPad)

                switch discoverVM.activeTab {
                case .trending:
                    trendingSection
                case .movies:
                    moviesSection
                case .tv:
                    tvSection
                case .upcoming:
                    upcomingSection
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable {
            await discoverVM.loadInitialData()
        }
    }

    // MARK: - Trending

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Trending Now")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(discoverVM.trendingItems) { result in
                        SeerrMediaCardView(
                            title: result.title,
                            year: nil,
                            posterURL: result.fullPosterURL,
                            status: result.mediaInfo?.status ?? .unknown,
                            cardWidth: cardWidth
                        )
                        .onTapGesture { openDetail(for: result) }
                    }
                }
                .padding(.horizontal, hPad)
            }
        }
    }

    // MARK: - Movies

    private var moviesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Genre pills
            genreFilterRow(
                genres: discoverVM.movieGenres,
                selected: discoverVM.selectedMovieGenre
            ) { genre in
                Task { await discoverVM.filterMoviesByGenre(genre) }
            }

            sectionHeader("Movies")

            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(discoverVM.movies) { movie in
                    SeerrMediaCardView(
                        title: movie.title,
                        year: movie.releaseYear,
                        posterURL: movie.fullPosterURL,
                        status: movie.availabilityStatus,
                        cardWidth: gridCardWidth
                    )
                    .onTapGesture { selectedResult = .movie(movie) }
                    .onAppear {
                        if movie.id == discoverVM.movies.last?.id {
                            Task { await discoverVM.loadMoreMovies() }
                        }
                    }
                }
            }
            .padding(.horizontal, hPad)

            if discoverVM.isLoadingMore {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - TV

    private var tvSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            genreFilterRow(
                genres: discoverVM.tvGenres,
                selected: discoverVM.selectedTVGenre
            ) { genre in
                Task { await discoverVM.filterTVByGenre(genre) }
            }

            sectionHeader("TV Shows")

            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(discoverVM.tvShows) { show in
                    SeerrMediaCardView(
                        title: show.name,
                        year: show.releaseYear,
                        posterURL: show.fullPosterURL,
                        status: show.availabilityStatus,
                        cardWidth: gridCardWidth
                    )
                    .onTapGesture { selectedResult = .tv(show) }
                    .onAppear {
                        if show.id == discoverVM.tvShows.last?.id {
                            Task { await discoverVM.loadMoreTV() }
                        }
                    }
                }
            }
            .padding(.horizontal, hPad)

            if discoverVM.isLoadingMore {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Upcoming

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Upcoming Movies")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(discoverVM.upcomingMovies) { movie in
                            SeerrMediaCardView(
                                title: movie.title,
                                year: movie.releaseYear,
                                posterURL: movie.fullPosterURL,
                                status: movie.availabilityStatus,
                                cardWidth: cardWidth
                            )
                            .onTapGesture { selectedResult = .movie(movie) }
                        }
                    }
                    .padding(.horizontal, hPad)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Upcoming TV Shows")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(discoverVM.upcomingTV) { show in
                            SeerrMediaCardView(
                                title: show.name,
                                year: show.releaseYear,
                                posterURL: show.fullPosterURL,
                                status: show.availabilityStatus,
                                cardWidth: cardWidth
                            )
                            .onTapGesture { selectedResult = .tv(show) }
                        }
                    }
                    .padding(.horizontal, hPad)
                }
            }
        }
    }

    // MARK: - No Seerr

    private var noSeerrView: some View {
        ContentUnavailableView {
            Label("Jellyseerr Not Configured", systemImage: "sparkles.tv")
        } description: {
            Text("Connect a Jellyseerr server in Settings to browse and request content.")
        } actions: {
            NavigationLink(destination: SeerrSetupView()) {
                Text("Connect Jellyseerr")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private func openDetail(for result: SeerrSearchResult) {
        switch result {
        case let .movie(m): selectedResult = .movie(m)
        case let .tv(t): selectedResult = .tv(t)
        case .person: break
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3)
            .fontWeight(.semibold)
            .padding(.horizontal, hPad)
    }

    private func genreFilterRow(
        genres: [SeerrGenre],
        selected: SeerrGenre?,
        onSelect: @escaping (SeerrGenre?) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                genrePill("All", isSelected: selected == nil) { onSelect(nil) }
                ForEach(genres) { genre in
                    genrePill(genre.name, isSelected: selected?.id == genre.id) { onSelect(genre) }
                }
            }
            .padding(.horizontal, hPad)
            .padding(.vertical, 4)
        }
    }

    private func genrePill(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.callout)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Platform sizing

    private var hPad: CGFloat {
        #if os(tvOS)
            return 60
        #else
            return 16
        #endif
    }

    private var cardWidth: CGFloat {
        #if os(tvOS)
            return 220
        #else
            return 130
        #endif
    }

    private var gridCardWidth: CGFloat {
        #if os(tvOS)
            return 240
        #else
            return 130
        #endif
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: gridCardWidth, maximum: gridCardWidth + 60), spacing: 12)]
    }
}
