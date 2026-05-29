// MARK: - LibraryView.swift

// Jellyswarrm — GPL v3 with App Store exception

import JellyswarrmCore
import SwiftUI

public struct LibraryView: View {
    public init() {}

    @Environment(LibraryViewModel.self) private var libraryVM
    @Environment(AppState.self) private var appState

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 20),
    ]

    #if os(tvOS)
        private let tvColumns = Array(
            repeating: GridItem(.fixed(200), spacing: 20),
            count: 4
        )
    #endif

    public var body: some View {
        NavigationStack {
            Group {
                if libraryVM.isLoading, libraryVM.sections.isEmpty {
                    ProgressView("Loading library...")
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if libraryVM.sections.isEmpty {
                    ContentUnavailableView(
                        "No Libraries",
                        systemImage: "film.stack",
                        description: Text("No libraries found on your Jellyfin server.")
                    )
                } else {
                    ScrollView {
                        #if os(tvOS)
                            LazyVGrid(columns: tvColumns, spacing: 24) {
                                ForEach(libraryVM.sections) { section in
                                    NavigationLink(destination: LibrarySectionView(section: section)) {
                                        TVLibrarySectionCard(section: section)
                                    }
                                    .buttonStyle(.plain)
                                    .focusEffectDisabled(true)
                                }
                            }
                            .padding(.horizontal, 60)
                            .padding(.vertical, 24)
                        #else
                            LazyVGrid(columns: columns, spacing: 24) {
                                ForEach(libraryVM.sections) { section in
                                    NavigationLink(destination: LibrarySectionView(section: section)) {
                                        librarySectionCard(section)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(gridPadding)
                        #endif
                    }
                }
            }
            .background(AppleTVTheme.background.ignoresSafeArea())
            .navigationTitle("Library")
            #if os(tvOS)
                .toolbar(.hidden, for: .navigationBar)
            #endif
            .refreshable {
                await libraryVM.refresh()
            }
            .navigationDestination(for: MediaItem.self) { item in
                MediaDetailView(item: item)
                    .environment(libraryVM)
            }
        }
    }

    private var gridPadding: CGFloat {
        #if os(tvOS)
            return 60
        #elseif os(macOS)
            return 32
        #else
            return 20
        #endif
    }

    private func librarySectionCard(_ section: LibrarySection) -> some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.07))
                    .aspectRatio(16 / 9, contentMode: .fit)

                Image(systemName: section.collectionType?.systemImageName ?? "folder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(section.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let count = section.childCount {
                    Text("\(count) items")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
    }
}

#if os(tvOS)
    // tvOS-native section card. Drives its own focus styling via @FocusState
    // and disables the system focus ring so neighbors aren't overlapped by a
    // white rounded-rect halo.
    private struct TVLibrarySectionCard: View {
        let section: LibrarySection
        @FocusState private var isFocused: Bool

        var body: some View {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                        .aspectRatio(16 / 9, contentMode: .fit)

                    Image(systemName: section.collectionType?.systemImageName ?? "folder.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.white.opacity(isFocused ? 1.0 : 0.6))
                }
                .scaleEffect(isFocused ? 1.06 : 1.0)
                .shadow(color: isFocused ? .white.opacity(0.3) : .clear, radius: 10)
                .animation(.easeInOut(duration: 0.15), value: isFocused)

                VStack(spacing: 2) {
                    Text(section.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let count = section.childCount {
                        Text("\(count) \(count == 1 ? "item" : "items")")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .background(Color.clear)
            .focusable(true) { focused in
                isFocused = focused
            }
            .focusEffectDisabled(true)
        }
    }
#endif

// MARK: - Library Section Grid

public struct LibrarySectionView: View {
    let section: LibrarySection

    public init(section: LibrarySection) {
        self.section = section
    }
    @Environment(LibraryViewModel.self) private var libraryVM

    @State private var items: [MediaItem] = []
    @State private var isLoading = false
    @State private var totalCount = 0
    @State private var currentPage = 0
    @State private var sortBy = "SortName"
    @State private var sortOrder = "Ascending"

    private let pageSize = 50

    private var cardWidth: CGFloat {
        #if os(tvOS)
            return 220
        #else
            return 140
        #endif
    }

    private var hPad: CGFloat {
        #if os(tvOS)
            return 60
        #elseif os(macOS)
            return 32
        #else
            return 20
        #endif
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 16, alignment: .top)]
    }

    private var itemNoun: String {
        switch section.collectionType {
        case .tvshows: return totalCount == 1 ? "Show" : "Shows"
        case .movies: return totalCount == 1 ? "Movie" : "Movies"
        case .music: return totalCount == 1 ? "Album" : "Albums"
        default: return totalCount == 1 ? "Item" : "Items"
        }
    }

    public var body: some View {
        ScrollView {
            if isLoading, items.isEmpty {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 80)
            } else {
                if totalCount > 0 {
                    HStack {
                        Text("\(totalCount) \(itemNoun)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    }
                    .padding(.horizontal, hPad)
                    .padding(.top, 12)
                }
                LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
                    ForEach(items) { item in
                        NavigationLink(destination: MediaDetailView(item: item).environment(libraryVM)) {
                            MediaCardView(
                                item: item,
                                imageURL: libraryVM.imageURL(for: item, type: .primary, maxWidth: 300),
                                cardWidth: cardWidth
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            // Load next page when near the end
                            if item.id == items.last?.id, items.count < totalCount {
                                Task { await loadNextPage() }
                            }
                        }
                    }

                    if isLoading, !items.isEmpty {
                        ProgressView()
                            .tint(.white)
                            .gridCellColumns(columns.count)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, hPad)
                .padding(.vertical, 16)

                if !isLoading, totalCount > 0 {
                    Text("\(items.count) of \(totalCount) \(itemNoun)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 24)
                }
            }
        }
        .background(AppleTVTheme.background.ignoresSafeArea())
        #if os(tvOS)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
        #else
            .navigationTitle(section.name)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Menu("Sort By") {
                        Button("Name") { setSortBy("SortName") }
                        Button("Date Added") { setSortBy("DateCreated") }
                        Button("Year") { setSortBy("ProductionYear") }
                        Button("Rating") { setSortBy("CommunityRating") }
                        Button("Runtime") { setSortBy("Runtime") }
                    }
                    Menu("Order") {
                        Button("Ascending") { sortOrder = "Ascending"; Task { await reload() } }
                        Button("Descending") { sortOrder = "Descending"; Task { await reload() } }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .task { await reload() }
    }

    private func setSortBy(_ sort: String) {
        sortBy = sort
        Task { await reload() }
    }

    private func reload() async {
        items = []
        currentPage = 0
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !isLoading else { return }
        isLoading = true
        do {
            let response = try await libraryVM.getItems(
                for: section,
                sortBy: sortBy,
                sortOrder: sortOrder,
                limit: pageSize,
                startIndex: currentPage * pageSize
            )
            items.append(contentsOf: response.items)
            totalCount = response.totalRecordCount
            currentPage += 1
        } catch {}
        isLoading = false
    }
}
