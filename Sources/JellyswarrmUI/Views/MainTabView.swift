// MARK: - MainTabView.swift

// Jellyswarrm — GPL v3 with App Store exception
// Adaptive navigation: TabView on iOS/tvOS, NavigationSplitView on macOS/iPadOS landscape

import JellyswarrmCore
import SwiftUI

public struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var libraryVM: LibraryViewModel
    @State private var discoverVM: DiscoverViewModel
    @State private var searchVM: SearchViewModel

    #if os(macOS)
        @State private var macOSSelection: MacOSSection? = .home

        enum MacOSSection: Hashable {
            case home, library, discover, search, settings
        }
    #endif

    public init() {
        // ViewModels initialized in body with environment — see .task below
        // Using temp placeholders here; real init happens in .task via onAppear
        _libraryVM = State(initialValue: LibraryViewModel(appState: AppState()))
        _discoverVM = State(initialValue: DiscoverViewModel(appState: AppState()))
        _searchVM = State(initialValue: SearchViewModel(appState: AppState()))
    }

    public var body: some View {
        #if os(macOS)
            macOSLayout
        #elseif os(tvOS)
            tvOSLayout
        #else
            iOSLayout
        #endif
    }

    // MARK: - iOS / iPadOS

    private var iOSLayout: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .environment(libraryVM)

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "film.stack")
                }
                .environment(libraryVM)

            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "sparkles.tv")
                }
                .environment(discoverVM)

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .environment(searchVM)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .environment(libraryVM)
        .environment(discoverVM)
        .environment(searchVM)
        .task { await setupViewModels() }
    }

    // MARK: - tvOS

    private var tvOSLayout: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            LibraryView()
                .tabItem { Label("Library", systemImage: "film.stack") }

            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles.tv") }

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environment(libraryVM)
        .environment(discoverVM)
        .environment(searchVM)
        .task { await setupViewModels() }
    }

    // MARK: - macOS

    #if os(macOS)
        private var macOSLayout: some View {
            NavigationSplitView {
                List(selection: $macOSSelection) {
                    Label("Home", systemImage: "house.fill").tag(MacOSSection.home)
                    Label("Library", systemImage: "film.stack").tag(MacOSSection.library)
                    Label("Discover", systemImage: "sparkles.tv").tag(MacOSSection.discover)
                    Label("Search", systemImage: "magnifyingglass").tag(MacOSSection.search)
                    Divider()
                    Label("Settings", systemImage: "gearshape").tag(MacOSSection.settings)
                }
                .listStyle(.sidebar)
                .navigationTitle("Jellyswarrm")
            } detail: {
                macOSDetail
                    .frame(minWidth: 600, minHeight: 400)
            }
            .environment(libraryVM)
            .environment(discoverVM)
            .environment(searchVM)
            .task { await setupViewModels() }
        }

        @ViewBuilder
        private var macOSDetail: some View {
            switch macOSSelection ?? .home {
            case .home: HomeView()
            case .library: LibraryView()
            case .discover: DiscoverView()
            case .search: SearchView()
            case .settings: SettingsView()
            }
        }
    #endif

    // MARK: - ViewModel Setup

    private func setupViewModels() async {
        libraryVM = LibraryViewModel(appState: appState)
        discoverVM = DiscoverViewModel(appState: appState)
        searchVM = SearchViewModel(appState: appState)

        async let libraryLoad: Void = libraryVM.refresh()
        async let discoverLoad: Void = discoverVM.loadInitialData()
        _ = await (libraryLoad, discoverLoad)
    }
}
