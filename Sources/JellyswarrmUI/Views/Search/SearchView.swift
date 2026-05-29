// MARK: - SearchView.swift

// Jellyswarrm — GPL v3 with App Store exception
// Unified search across Jellyfin library + Seerr discover

import JellyswarrmCore
import SwiftUI

public struct SearchView: View {
    public init() {}

    @Environment(SearchViewModel.self) private var searchVM
    @Environment(LibraryViewModel.self) private var libraryVM
    @Environment(AppState.self) private var appState

    @State private var selectedSeerrResult: SeerrSearchResult?

    public var body: some View {
        NavigationStack {
            @Bindable var searchVM = searchVM
            List {
                if searchVM.query.isEmpty {
                    emptyStateView
                } else if searchVM.isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Searching...")
                            Spacer()
                        }
                    }
                } else {
                    // Jellyfin results — items already on server
                    if !searchVM.jellyfinResults.isEmpty {
                        Section("In Your Library") {
                            ForEach(searchVM.jellyfinResults) { item in
                                NavigationLink(destination: MediaDetailView(item: item).environment(libraryVM)) {
                                    libraryRow(item: item)
                                }
                            }
                        }
                    }

                    // Seerr results — items that can be requested
                    if !searchVM.discoverableResults.isEmpty, appState.hasSeerrConfigured {
                        Section("Discover & Request") {
                            ForEach(searchVM.discoverableResults) { result in
                                Button {
                                    selectedSeerrResult = result
                                } label: {
                                    seerrRow(result: result)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if searchVM.jellyfinResults.isEmpty, searchVM.seerrResults.isEmpty {
                        Section {
                            ContentUnavailableView.search(text: searchVM.query)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            #if os(macOS) || os(tvOS)
            .listStyle(.plain)
            #else
            .listStyle(.grouped)
            #endif
            .navigationTitle("Search")
            #if os(tvOS)
                .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(for: MediaItem.self) { item in
                MediaDetailView(item: item)
                    .environment(libraryVM)
            }
            .searchable(text: $searchVM.query, prompt: "Search movies, shows, episodes...")
            .onChange(of: searchVM.query) { _, newValue in
                searchVM.queryChanged(newValue)
            }
            #if os(tvOS)
                .navigationDestination(isPresented: Binding(
                    get: { selectedSeerrResult != nil },
                    set: { newValue in if !newValue { selectedSeerrResult = nil } }
                )) {
                    seerrDetailDestination
                }
            #else
                .sheet(item: $selectedSeerrResult) { result in
                    switch result {
                    case let .movie(m):
                        SeerrDetailView(movie: m)
                            .environment(DiscoverViewModel(appState: appState))
                    case let .tv(t):
                        SeerrDetailView(tv: t)
                            .environment(DiscoverViewModel(appState: appState))
                    case .person:
                        EmptyView()
                    }
                }
            #endif
        }
    }

    @ViewBuilder
    private var seerrDetailDestination: some View {
        if let result = selectedSeerrResult {
            switch result {
            case let .movie(m):
                SeerrDetailView(movie: m)
                    .environment(DiscoverViewModel(appState: appState))
            case let .tv(t):
                SeerrDetailView(tv: t)
                    .environment(DiscoverViewModel(appState: appState))
            case .person:
                EmptyView()
            }
        }
    }

    private var emptyStateView: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Search your library and discover content to request")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
        .listRowBackground(Color.clear)
    }

    private func libraryRow(item: MediaItem) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: libraryVM.imageURL(for: item, type: .primary, maxWidth: 80)) { phase in
                if case let .success(image) = phase {
                    image.resizable()
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .frame(width: 44, height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 44, height: 66)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(item.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let year = item.productionYear {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let userData = item.userData, userData.hasProgress {
                    ProgressView(value: userData.normalizedProgress)
                        .tint(Color.accentColor)
                        .frame(maxWidth: 120)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func seerrRow(result: SeerrSearchResult) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: result.fullPosterURL) { phase in
                if case let .success(image) = phase {
                    image.resizable()
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .frame(width: 44, height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 44, height: 66)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(result.mediaType == "movie" ? "Movie" : "TV Show")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let status = result.mediaInfo?.status {
                    Text(status.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(status.isOnServer ? .green : .orange)
                }
            }

            Spacer()

            Image(systemName: "plus.circle")
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 4)
    }
}
