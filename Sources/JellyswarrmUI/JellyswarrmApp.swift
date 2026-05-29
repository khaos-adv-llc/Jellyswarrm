// MARK: - JellyswarrmApp.swift

// Jellyswarrm — LGPL-2.1-or-later

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
    ///    server configs → show TVUserSwitchView (quick-connect or fresh setup).
    /// 2. No saved servers → show OnboardingWizardView (fresh install).
    /// 3. Not authenticated against current server → show LoginView.
    /// 4. Authenticated → show main app.
    #if os(tvOS)
        @ViewBuilder
        private var tvOSRootView: some View {
            if appState.needsTVOSUserOnboarding {
                // New tvOS profile detected: offer quick-connect or fresh setup.
                TVUserSwitchView()
            } else if appState.isOnboarding {
                // Wizard still in progress (e.g. user has signed in but hasn't
                // reached the final step yet). Keep showing it.
                OnboardingWizardView()
            } else if appState.isAuthenticated, appState.currentServer != nil {
                MainTabView()
            } else if appState.savedServers.isEmpty {
                OnboardingWizardView()
            } else {
                LoginView()
            }
        }
    #endif

    // MARK: iOS / iPadOS / macOS

    @ViewBuilder
    private var defaultRootView: some View {
        if appState.isOnboarding {
            OnboardingWizardView()
        } else if appState.isAuthenticated, appState.currentServer != nil {
            MainTabView()
        } else if appState.savedServers.isEmpty {
            OnboardingWizardView()
        } else {
            LoginView()
        }
    }
}
