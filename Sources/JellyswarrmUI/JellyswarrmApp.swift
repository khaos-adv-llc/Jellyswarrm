// MARK: - JellyswarrmApp.swift

// Jellyswarrm — GPL v3 with App Store exception

import JellyswarrmCore
import SwiftUI

// MARK: - Root Router

public struct RootView: View {
    public init() {}

    @Environment(AppState.self) private var appState

    public var body: some View {
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
