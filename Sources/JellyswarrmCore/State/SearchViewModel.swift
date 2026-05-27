// MARK: - SearchViewModel.swift

// Jellyswarrm — GPL v3 with App Store exception

import Foundation
import Observation

@Observable
@MainActor
public final class SearchViewModel {
    public var query: String = ""
    public var jellyfinResults: [MediaItem] = []
    public var seerrResults: [SeerrSearchResult] = []
    public var isSearching: Bool = false
    public var error: NetworkError?

    private var searchTask: Task<Void, Never>?
    private let appState: AppState
    private let jellyfinAPI = JellyfinAPIClient.shared
    private let seerrAPI = SeerrAPIClient.shared

    public init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Credential helper

    private var seerrCredential: SeerrCredential? {
        appState.credentialForCurrentSeerrServer()
    }

    /// Call when query changes — debounces automatically
    public func queryChanged(_ newQuery: String) {
        query = newQuery
        searchTask?.cancel()

        guard !newQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            jellyfinResults = []
            seerrResults = []
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms debounce
            guard !Task.isCancelled else { return }
            await performSearch(query: newQuery)
        }
    }

    private func performSearch(query: String) async {
        isSearching = true
        error = nil

        await withTaskGroup(of: Void.self) { group in
            // Search Jellyfin
            if let server = appState.currentServer,
               let token = appState.tokenForCurrentServer()
            {
                group.addTask {
                    do {
                        let results = try await self.jellyfinAPI.searchItems(
                            server: server,
                            token: token,
                            query: query
                        )
                        await MainActor.run { self.jellyfinResults = results }
                    } catch {}
                }
            }

            // Search Seerr
            if let seerrServer = appState.seerrServer,
               let cred = seerrCredential
            {
                group.addTask {
                    do {
                        let page = try await self.seerrAPI.search(
                            baseURL: seerrServer.baseURL,
                            credential: cred,
                            query: query
                        )
                        await MainActor.run { self.seerrResults = page.results }
                    } catch {}
                }
            }
        }

        isSearching = false
    }

    public func clear() {
        searchTask?.cancel()
        query = ""
        jellyfinResults = []
        seerrResults = []
        isSearching = false
        error = nil
    }

    /// Seerr results filtered to items NOT already on the Jellyfin server
    public var discoverableResults: [SeerrSearchResult] {
        seerrResults.filter { result in
            guard let info = result.mediaInfo else { return true }
            return !info.status.isOnServer
        }
    }

    /// Seerr results that ARE on the server (useful for cross-referencing)
    public var onServerSeerrResults: [SeerrSearchResult] {
        seerrResults.filter { $0.mediaInfo?.status.isOnServer == true }
    }
}
