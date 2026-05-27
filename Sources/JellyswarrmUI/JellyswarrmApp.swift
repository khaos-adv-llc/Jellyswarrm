// MARK: - JellyswarrmApp.swift

// Jellyswarrm — GPL v3 with App Store exception

import JellyswarrmCore
import SwiftUI

@main
struct JellyswarrmApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task {
                    appState.loadFromStorage()
                    #if os(tvOS)
                        // Check whether this tvOS system profile needs onboarding
                        // (runs asynchronously; RootView reacts to the published property)
                        appState.checkTVOSUserOnboarding()
                    #endif
                }
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        #endif
    }
}

// MARK: - Root Router

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            #if os(tvOS)
                tvOSRootView
            #else
                defaultRootView
            #endif
        }
        .animation(.easeInOut, value: appState.isAuthenticated)
    }

    // MARK: tvOS

    /// tvOS routing layer.
    ///
    /// Priority order:
    /// 1. `needsTVOSUserOnboarding` — a new system profile detected with existing
    ///    server configs → show TVOSUserWelcomeView (server selection + login).
    /// 2. Not authenticated yet → show LoginView (fresh install / new server setup).
    /// 3. Authenticated → show main app.
    #if os(tvOS)
        @ViewBuilder
        private var tvOSRootView: some View {
            if appState.needsTVOSUserOnboarding {
                // New tvOS profile: let user pick a known server and sign in
                TVOSUserWelcomeView()
            } else if appState.isAuthenticated, appState.currentServer != nil {
                MainTabView()
            } else {
                LoginView()
            }
        }
    #endif

    // MARK: iOS / iPadOS / macOS

    @ViewBuilder
    private var defaultRootView: some View {
        if appState.isAuthenticated, appState.currentServer != nil {
            MainTabView()
        } else {
            LoginView()
        }
    }
}
