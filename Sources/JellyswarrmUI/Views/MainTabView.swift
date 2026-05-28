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
                .environment(libraryVM)

            LibraryView()
                .tabItem { Label("Library", systemImage: "film.stack") }
                .environment(libraryVM)

            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles.tv") }
                .environment(discoverVM)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .environment(searchVM)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { await setupViewModels() }
    }

    // MARK: - macOS

    #if !os(tvOS)
        private var macOSLayout: some View {
            NavigationSplitView {
                List {
                    NavigationLink(destination: HomeView().environment(libraryVM)) {
                        Label("Home", systemImage: "house.fill")
                    }
                    NavigationLink(destination: LibraryView().environment(libraryVM)) {
                        Label("Library", systemImage: "film.stack")
                    }
                    NavigationLink(destination: DiscoverView().environment(discoverVM)) {
                        Label("Discover", systemImage: "sparkles.tv")
                    }
                    NavigationLink(destination: SearchView().environment(searchVM)) {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    Divider()
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("Jellyswarrm")
            } detail: {
                HomeView()
                    .environment(libraryVM)
            }
            .task { await setupViewModels() }
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
