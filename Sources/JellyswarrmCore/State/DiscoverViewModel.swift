// MARK: - DiscoverViewModel.swift

// Jellyswarrm — GPL v3 with App Store exception

import Foundation
import Observation

public enum DiscoverMediaTab: String, CaseIterable, Identifiable {
    case trending = "Trending"
    case movies = "Movies"
    case tv = "TV Shows"
    case upcoming = "Upcoming"

    public var id: String { rawValue }
}

@Observable
@MainActor
public final class DiscoverViewModel {
    // MARK: - State

    public var activeTab: DiscoverMediaTab = .trending
    public var trendingItems: [SeerrSearchResult] = []
    public var movies: [SeerrMovieResult] = []
    public var tvShows: [SeerrTvResult] = []
    public var upcomingMovies: [SeerrMovieResult] = []
    public var upcomingTV: [SeerrTvResult] = []

    public var movieGenres: [SeerrGenre] = []
    public var tvGenres: [SeerrGenre] = []
    public var selectedMovieGenre: SeerrGenre?
    public var selectedTVGenre: SeerrGenre?

    public var isLoading: Bool = false
    public var isLoadingMore: Bool = false
    public var error: NetworkError?

    // Pagination
    private var trendingPage = 1
    private var moviesPage = 1
    private var tvPage = 1
    private var hasMoreTrending = true
    private var hasMoreMovies = true
    private var hasMoreTV = true

    // Request tracking
    public var pendingRequestIds: Set<Int> = []
    public var successfulRequestIds: Set<Int> = []

    private let appState: AppState
    private let seerrAPI = SeerrAPIClient.shared

    public init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Credential helper

    /// Returns the resolved SeerrCredential for the current user, or nil if Seerr
    /// is not configured or the user has not yet authenticated.
    private var credential: SeerrCredential? {
        appState.credentialForCurrentSeerrServer()
    }

    // MARK: - Load

    public func loadInitialData() async {
        guard appState.hasSeerrConfigured,
              let server = appState.seerrServer,
              let cred = credential else { return }

        isLoading = true
        error = nil

        do {
            async let trendingTask = seerrAPI.discoverTrending(baseURL: server.baseURL, credential: cred)
            async let moviesTask = seerrAPI.discoverMovies(baseURL: server.baseURL, credential: cred)
            async let tvTask = seerrAPI.discoverTV(baseURL: server.baseURL, credential: cred)
            async let upcomingMoviesTask = seerrAPI.discoverMoviesUpcoming(baseURL: server.baseURL, credential: cred)
            async let upcomingTVTask = seerrAPI.discoverTVUpcoming(baseURL: server.baseURL, credential: cred)
            async let movieGenresTask = seerrAPI.getMovieGenres(baseURL: server.baseURL, credential: cred)
            async let tvGenresTask = seerrAPI.getTVGenres(baseURL: server.baseURL, credential: cred)

            let (trending, movs, tv, upMovies, upTV, mGenres, tGenres) = try await (
                trendingTask, moviesTask, tvTask,
                upcomingMoviesTask, upcomingTVTask,
                movieGenresTask, tvGenresTask
            )

            trendingItems = trending.results
            trendingPage = trending.pageInfo.page
            hasMoreTrending = trending.pageInfo.page < trending.pageInfo.pages

            movies = movs.results
            moviesPage = movs.pageInfo.page
            hasMoreMovies = movs.pageInfo.page < movs.pageInfo.pages

            tvShows = tv.results
            tvPage = tv.pageInfo.page
            hasMoreTV = tv.pageInfo.page < tv.pageInfo.pages

            upcomingMovies = upMovies.results
            upcomingTV = upTV.results

            movieGenres = mGenres
            tvGenres = tGenres

        } catch let e as NetworkError {
            error = e
        } catch {
            self.error = .custom(error.localizedDescription)
        }

        isLoading = false
    }

    // MARK: - Load More (pagination)

    public func loadMoreMovies() async {
        guard !isLoadingMore, hasMoreMovies,
              let server = appState.seerrServer,
              let cred = credential else { return }

        isLoadingMore = true
        let nextPage = moviesPage + 1
        do {
            let page = try await seerrAPI.discoverMovies(
                baseURL: server.baseURL,
                credential: cred,
                page: nextPage,
                genre: selectedMovieGenre?.id
            )
            movies.append(contentsOf: page.results)
            moviesPage = page.pageInfo.page
            hasMoreMovies = page.pageInfo.page < page.pageInfo.pages
        } catch {}
        isLoadingMore = false
    }

    public func loadMoreTV() async {
        guard !isLoadingMore, hasMoreTV,
              let server = appState.seerrServer,
              let cred = credential else { return }

        isLoadingMore = true
        let nextPage = tvPage + 1
        do {
            let page = try await seerrAPI.discoverTV(
                baseURL: server.baseURL,
                credential: cred,
                page: nextPage,
                genre: selectedTVGenre?.id
            )
            tvShows.append(contentsOf: page.results)
            tvPage = page.pageInfo.page
            hasMoreTV = page.pageInfo.page < page.pageInfo.pages
        } catch {}
        isLoadingMore = false
    }

    // MARK: - Genre Filtering

    public func filterMoviesByGenre(_ genre: SeerrGenre?) async {
        selectedMovieGenre = genre
        guard let server = appState.seerrServer,
              let cred = credential else { return }
        do {
            let page = try await seerrAPI.discoverMovies(
                baseURL: server.baseURL,
                credential: cred,
                page: 1,
                genre: genre?.id
            )
            movies = page.results
            moviesPage = 1
            hasMoreMovies = page.pageInfo.page < page.pageInfo.pages
        } catch {}
    }

    public func filterTVByGenre(_ genre: SeerrGenre?) async {
        selectedTVGenre = genre
        guard let server = appState.seerrServer,
              let cred = credential else { return }
        do {
            let page = try await seerrAPI.discoverTV(
                baseURL: server.baseURL,
                credential: cred,
                page: 1,
                genre: genre?.id
            )
            tvShows = page.results
            tvPage = 1
            hasMoreTV = page.pageInfo.page < page.pageInfo.pages
        } catch {}
    }

    // MARK: - Requesting Media

    public func requestMovie(movieId: Int) async throws {
        guard let server = appState.seerrServer,
              let cred = credential
        else {
            throw NetworkError.unauthorized
        }
        pendingRequestIds.insert(movieId)
        do {
            _ = try await seerrAPI.createRequest(
                baseURL: server.baseURL,
                credential: cred,
                request: RequestCreate(mediaType: "movie", mediaId: movieId)
            )
            successfulRequestIds.insert(movieId)
        } catch {
            pendingRequestIds.remove(movieId)
            throw error
        }
        pendingRequestIds.remove(movieId)
    }

    public func requestTV(tvId: Int, seasons: [Int]? = nil) async throws {
        guard let server = appState.seerrServer,
              let cred = credential
        else {
            throw NetworkError.unauthorized
        }
        pendingRequestIds.insert(tvId)
        do {
            _ = try await seerrAPI.createRequest(
                baseURL: server.baseURL,
                credential: cred,
                request: RequestCreate(mediaType: "tv", mediaId: tvId, seasons: seasons)
            )
            successfulRequestIds.insert(tvId)
        } catch {
            pendingRequestIds.remove(tvId)
            throw error
        }
        pendingRequestIds.remove(tvId)
    }

    public func requestStatus(for mediaId: Int) -> RequestButtonState {
        if successfulRequestIds.contains(mediaId) { return .requested }
        if pendingRequestIds.contains(mediaId) { return .requesting }
        return .available
    }

    public enum RequestButtonState {
        case available // can request
        case requesting // in-flight
        case requested // successfully submitted
        case onServer // already available
        case pending // request pending admin approval
    }

    public func buttonState(for mediaInfo: SeerrMediaInfo?, mediaId: Int) -> RequestButtonState {
        if successfulRequestIds.contains(mediaId) { return .requested }
        if pendingRequestIds.contains(mediaId) { return .requesting }
        guard let info = mediaInfo else { return .available }
        switch info.status {
        case .available: return .onServer
        case .partiallyAvailable: return .onServer
        case .pending, .processing: return .pending
        default: return .available
        }
    }
}
