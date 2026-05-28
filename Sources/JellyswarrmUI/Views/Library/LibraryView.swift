// MARK: - LibraryView.swift

// Jellyswarrm — GPL v3 with App Store exception

import JellyswarrmCore
import SwiftUI

public struct LibraryView: View {
    public init() {}

    @Environment(LibraryViewModel.self) private var libraryVM
    @Environment(AppState.self) private var appState

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16),
    ]

    public var body: some View {
        NavigationStack {
            Group {
                if libraryVM.isLoading, libraryVM.sections.isEmpty {
                    ProgressView("Loading library...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if libraryVM.sections.isEmpty {
                    ContentUnavailableView(
                        "No Libraries",
                        systemImage: "film.stack",
                        description: Text("No libraries found on your Jellyfin server.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(libraryVM.sections) { section in
                                NavigationLink(destination: LibrarySectionView(section: section)) {
                                    librarySectionCard(section)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Library")
            .refreshable {
                await libraryVM.refresh()
            }
        }
    }

    private func librarySectionCard(_ section: LibrarySection) -> some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.15))
                    .aspectRatio(16 / 9, contentMode: .fit)

                Image(systemName: section.collectionType?.systemImageName ?? "folder")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(section.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if let count = section.childCount {
                    Text("\(count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

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
    private let cardWidth: CGFloat = 130
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 12, alignment: .top)]
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
                ProgressView().padding(.top, 80)
            } else {
                if totalCount > 0 {
                    HStack {
                        Text("\(totalCount) \(itemNoun)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
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
                        ProgressView().gridCellColumns(columns.count)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()

                if !isLoading, totalCount > 0 {
                    Text("\(items.count) of \(totalCount) \(itemNoun)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom)
                }
            }
        }
        .navigationTitle(section.name)
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
