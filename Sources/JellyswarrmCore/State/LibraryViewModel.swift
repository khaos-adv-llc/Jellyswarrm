// MARK: - LibraryViewModel.swift

// Jellyswarrm — LGPL-2.1-or-later

import Foundation
import Observation

@Observable
@MainActor
public final class LibraryViewModel {
    public var sections: [LibrarySection] = []
    public var continueWatching: [MediaItem] = []
    public var nextUp: [MediaItem] = []
    public var recentlyAdded: [String: [MediaItem]] = [:] // keyed by section id
    public var isLoading: Bool = false
    public var error: NetworkError?

    private let appState: AppState
    private let api = JellyfinAPIClient.shared

    public init(appState: AppState) {
        self.appState = appState
    }

    public func refresh() async {
        guard let server = appState.currentServer,
              let token = appState.tokenForCurrentServer() else { return }

        isLoading = true
        error = nil

        do {
            async let sectionsTask = api.getLibrarySections(server: server, token: token)
            async let cwTask = api.getContinueWatching(server: server, token: token)
            async let nextUpTask = api.getNextUp(server: server, token: token)

            let (newSections, cw, nu) = try await (sectionsTask, cwTask, nextUpTask)
            sections = newSections
            continueWatching = cw
            nextUp = nu

            // Load recently added for each section in parallel
            await loadRecentlyAdded(sections: newSections, server: server, token: token)
        } catch let e as NetworkError {
            error = e
        } catch {
            self.error = .custom(error.localizedDescription)
        }

        isLoading = false
    }

    private func loadRecentlyAdded(sections: [LibrarySection], server: JellyfinServer, token: String) async {
        await withTaskGroup(of: (String, [MediaItem]).self) { group in
            for section in sections {
                group.addTask {
                    let items = await (try? self.api.getItems(
                        server: server,
                        token: token,
                        parentId: section.id,
                        sortBy: "DateCreated",
                        sortOrder: "Descending",
                        limit: 12,
                        recursive: true,
                        includeItemTypes: ["Movie", "Series", "Episode"]
                    ))?.items ?? []
                    return (section.id, items)
                }
            }
            for await (sectionId, items) in group {
                recentlyAdded[sectionId] = items
            }
        }
    }

    public func getItems(
        for section: LibrarySection,
        sortBy: String = "SortName",
        sortOrder: String = "Ascending",
        limit: Int = 50,
        startIndex: Int = 0
    ) async throws -> ItemsResponse<MediaItem> {
        guard let server = appState.currentServer,
              let token = appState.tokenForCurrentServer()
        else {
            throw NetworkError.unauthorized
        }
        // Per-collection item types so the library shows one entry per Series
        // (not per Season), Movie, or Album — matches Jellyfin/Swiftfin behaviour.
        let includeTypes: [String]
        switch section.collectionType {
        case .tvshows: includeTypes = ["Series"]
        case .movies: includeTypes = ["Movie"]
        case .music: includeTypes = ["MusicAlbum"]
        default: includeTypes = []
        }
        // For TV/Movies/Music we want a flat list across all subfolders, so recursive=true
        // — required when filtering by IncludeItemTypes.
        let recursive = !includeTypes.isEmpty
        return try await api.getItems(
            server: server,
            token: token,
            parentId: section.id,
            sortBy: sortBy,
            sortOrder: sortOrder,
            limit: limit,
            startIndex: startIndex,
            recursive: recursive,
            includeItemTypes: includeTypes
        )
    }

    public func getDetail(for itemId: String) async throws -> MediaItem {
        guard let server = appState.currentServer,
              let token = appState.tokenForCurrentServer()
        else {
            throw NetworkError.unauthorized
        }
        return try await api.getItemDetail(server: server, token: token, itemId: itemId)
    }

    public func getSeasons(for seriesId: String) async throws -> [MediaItem] {
        guard let server = appState.currentServer,
              let token = appState.tokenForCurrentServer()
        else {
            throw NetworkError.unauthorized
        }
        return try await api.getSeasons(server: server, token: token, seriesId: seriesId)
    }

    public func getEpisodes(for seriesId: String, seasonId: String? = nil) async throws -> [MediaItem] {
        guard let server = appState.currentServer,
              let token = appState.tokenForCurrentServer()
        else {
            throw NetworkError.unauthorized
        }
        return try await api.getEpisodes(server: server, token: token, seriesId: seriesId, seasonId: seasonId)
    }

    public func toggleFavorite(_ item: MediaItem) async throws {
        // Optimistic UI update would go here — full implementation in real app
        _ = try await getDetail(for: item.id)
    }

    @discardableResult
    public func setPlayed(_ played: Bool, itemId: String) async throws -> UserData {
        guard let server = appState.currentServer,
              let token = appState.tokenForCurrentServer()
        else {
            throw NetworkError.unauthorized
        }
        if played {
            return try await api.markPlayed(server: server, token: token, itemId: itemId)
        } else {
            return try await api.markUnplayed(server: server, token: token, itemId: itemId)
        }
    }

    public func imageURL(for item: MediaItem, type: ImageType = .primary, maxWidth: Int = 400) -> URL? {
        guard let server = appState.currentServer else { return nil }
        let tag: String? = switch type {
        case .primary: item.primaryImageTag
        case .backdrop: item.firstBackdropTag
        case .thumb: item.thumbImageTag
        case .logo: item.logoImageTag
        default: nil
        }
        guard tag != nil else { return nil }
        return api.imageURL(server: server, itemId: item.id, imageType: type, tag: tag, maxWidth: maxWidth)
    }

    /// Poster URL for a card. For episodes, prefers the parent series' primary art so that
    /// "Continue Watching" / "Next Up" rows show the show banner instead of the episode still.
    /// Falls back to the series backdrop, then to the episode's own image.
    public func posterImageURL(for item: MediaItem, maxWidth: Int = 400) -> URL? {
        guard let server = appState.currentServer else {
            return imageURL(for: item, type: .primary, maxWidth: maxWidth)
        }
        if item.type == .episode, let seriesId = item.seriesId {
            if let tag = item.seriesPrimaryImageTag {
                return api.imageURL(server: server, itemId: seriesId, imageType: .primary, tag: tag, maxWidth: maxWidth)
            }
            return api.imageURL(server: server, itemId: seriesId, imageType: .backdrop, tag: nil, maxWidth: maxWidth)
        }
        return imageURL(for: item, type: .primary, maxWidth: maxWidth)
    }
}
