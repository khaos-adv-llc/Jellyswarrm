// MARK: - DiscoverView.swift

// Jellyswarrm — GPL v3 with App Store exception
// Seerr-powered discover section: browse trending, upcoming, by genre.
// Items show availability status and request buttons directly.

import JellyswarrmCore
import SwiftUI

public struct DiscoverView: View {
    public init() {}

    @Environment(DiscoverViewModel.self) private var discoverVM
    @Environment(AppState.self) private var appState

    @State private var selectedResult: DiscoverDetailTarget?

    enum DiscoverDetailTarget: Identifiable, Hashable {
        case movie(SeerrMovieResult)
        case tv(SeerrTvResult)
        var id: String {
            switch self {
            case let .movie(m): return "m\(m.id)"
            case let .tv(t): return "t\(t.id)"
            }
        }

        static func == (lhs: DiscoverDetailTarget, rhs: DiscoverDetailTarget) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if !appState.hasSeerrConfigured {
                    noSeerrView
                } else if let error = discoverVM.error, discoverVM.trendingItems.isEmpty {
                    errorView(error)
                } else if discoverVM.isLoading, discoverVM.trendingItems.isEmpty {
                    ProgressView("Loading Discover...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if discoverVM.trendingItems.isEmpty,
                          discoverVM.movies.isEmpty,
                          discoverVM.tvShows.isEmpty,
                          !discoverVM.isLoading {
                    emptyResultsView
                } else {
                    discoverContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Discover")
            #if os(tvOS)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $selectedResult) { target in
                    switch target {
                    case let .movie(m): SeerrDetailView(movie: m).environment(discoverVM)
                    case let .tv(t): SeerrDetailView(tv: t).environment(discoverVM)
                    }
                }
            #else
                .sheet(item: $selectedResult) { target in
                    switch target {
                    case let .movie(m): SeerrDetailView(movie: m)
                    case let .tv(t): SeerrDetailView(tv: t)
                    }
                }
            #endif
            .task(id: appState.seerrServer?.id) {
                guard appState.hasSeerrConfigured,
                      discoverVM.trendingItems.isEmpty,
                      !discoverVM.isLoading else { return }
                await discoverVM.loadInitialData()
            }
        }
    }

    // MARK: - Main Content

    private var discoverContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !discoverVM.trendingMovies.isEmpty {
                    movieRow(title: "Trending Movies", movies: discoverVM.trendingMovies)
                }

                if !discoverVM.trendingTV.isEmpty {
                    tvRow(title: "Trending TV", shows: discoverVM.trendingTV)
                }

                if !discoverVM.trendingItems.isEmpty {
                    mixedRow(title: "Popular This Week", items: discoverVM.trendingItems)
                }

                if !discoverVM.upcomingMovies.isEmpty {
                    movieRow(title: "Upcoming Movies", movies: discoverVM.upcomingMovies)
                }

                if !discoverVM.upcomingTV.isEmpty {
                    tvRow(title: "Upcoming TV Shows", shows: discoverVM.upcomingTV)
                }

                if !discoverVM.movies.isEmpty {
                    movieRow(
                        title: "Movies",
                        movies: discoverVM.movies,
                        loadMore: { await discoverVM.loadMoreMovies() }
                    )
                }

                if !discoverVM.tvShows.isEmpty {
                    tvRow(
                        title: "TV Shows",
                        shows: discoverVM.tvShows,
                        loadMore: { await discoverVM.loadMoreTV() }
                    )
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.07).ignoresSafeArea())
        #if !os(tvOS)
            .refreshable {
                await discoverVM.loadInitialData()
            }
        #endif
    }

    // MARK: - Shelf Rows

    private func movieRow(
        title: String,
        movies: [SeerrMovieResult],
        loadMore: (() async -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(movies) { movie in
                        SeerrMediaCardView(
                            title: movie.title,
                            year: movie.releaseYear,
                            posterURL: movie.fullPosterURL,
                            status: movie.availabilityStatus,
                            cardWidth: cardWidth
                        )
                        .onTapGesture { selectedResult = .movie(movie) }
                        .onAppear {
                            if let loadMore, movie.id == movies.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }
                }
                .padding(.horizontal, hPad)
            }
        }
    }

    private func tvRow(
        title: String,
        shows: [SeerrTvResult],
        loadMore: (() async -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(shows) { show in
                        SeerrMediaCardView(
                            title: show.name,
                            year: show.releaseYear,
                            posterURL: show.fullPosterURL,
                            status: show.availabilityStatus,
                            cardWidth: cardWidth
                        )
                        .onTapGesture { selectedResult = .tv(show) }
                        .onAppear {
                            if let loadMore, show.id == shows.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }
                }
                .padding(.horizontal, hPad)
            }
        }
    }

    private func mixedRow(title: String, items: [SeerrSearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(items) { result in
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

    // MARK: - Empty / Error States

    private var noSeerrView: some View {
        ContentUnavailableView {
            Label("Seerr Not Configured", systemImage: "sparkles.tv")
        } description: {
            Text("Connect a Seerr server in Settings to browse and request content.")
        } actions: {
            NavigationLink(destination: SeerrSetupView()) {
                Text("Connect Seerr")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func errorView(_ error: NetworkError) -> some View {
        ContentUnavailableView {
            Label("Couldn't Load Discover", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button {
                Task { await discoverVM.loadInitialData() }
            } label: {
                Text("Retry").fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyResultsView: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
        } description: {
            Text("Nothing to show here yet. Pull to refresh or try again later.")
        } actions: {
            Button {
                Task { await discoverVM.loadInitialData() }
            } label: {
                Text("Refresh").fontWeight(.semibold)
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
            .font(.title2)
            .fontWeight(.bold)
            .padding(.horizontal, hPad)
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
}
