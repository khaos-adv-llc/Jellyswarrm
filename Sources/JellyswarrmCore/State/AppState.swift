// MARK: - AppState.swift

// Jellyswarrm — LGPL-2.1-or-later
//
// tvOS multi-user strategy:
//   "Runs as Current User" entitlement → OS re-launches app per tvOS profile.
//   Shared storage  (App Group UserDefaults + shared Keychain) → server IDs, server configs, Seerr configs, API keys.
//   Per-user storage (regular Keychain + standard UserDefaults)  → Jellyfin tokens, Seerr session cookies.
//
// On launch AppState checks: shared configs exist but no per-user token → needsTVOSUserOnboarding = true.

import Foundation
import Observation
#if canImport(UIKit)
    import UIKit
#endif

@Observable
@MainActor
public final class AppState {
    // MARK: - Published State

    public var currentServer: JellyfinServer?
    public var seerrServer: SeerrServer?
    public var isAuthenticated: Bool = false
    public var savedServers: [JellyfinServer] = []
    public var savedSeerrServers: [SeerrServer] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    // MARK: - tvOS Multi-User State

    /// True when a tvOS profile switch is detected and this profile has no token yet.
    public var needsTVOSUserOnboarding: Bool = false

    /// True while the multi-step onboarding wizard is in progress. The router
    /// uses this to keep showing the wizard after Jellyfin sign-in so the user
    /// can continue to the Seerr setup steps instead of jumping straight to Home.
    public var isOnboarding: Bool = false

    /// Server configs readable from shared storage — populated before per-user auth.
    public var sharedServerConfigs: [JellyfinServer] = []

    // MARK: - UserDefaults Keys

    // Standard UserDefaults are per-user on tvOS with "Runs as Current User".
    // App Group UserDefaults are device-wide (shared between profiles).

    private let activeServerIdKey = "jellyswarrm_active_server_id"
    private let activeSeerrIdKey = "jellyswarrm_active_seerr_server_id"
    private let serverIdsKey = "jellyswarrm_server_ids"
    private let seerrServerIdsKey = "jellyswarrm_seerr_server_ids"

    // Shared App Group keys for tvOS multi-user quick-connect hints.
    private let lastServerURLKey = "lastServerURL"
    private let lastSeerrURLKey = "lastSeerrURL"
    private let lastSeerrAuthModeKey = "lastSeerrAuthMode"

    /// App Group suite — device-wide, readable by all tvOS profiles.
    /// Must match the App Group entitlement: com.jellyswarrm.shared
    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: "group.com.jellyswarrm.shared") ?? .standard
    }

    public init() {
        #if os(tvOS)
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleForegroundTransition() }
            }
        #endif
        // Load persisted server configs and auth state synchronously so that
        // RootView renders the correct destination on the very first frame —
        // not onboarding — when the user has already set up the app.
        loadFromStorage()
    }

    // MARK: - tvOS Foreground Transition

    /// Re-read storage when the app foregrounds. On tvOS the OS may swap the
    /// per-user sandbox during a profile switch, so the in-memory state can be
    /// stale and the per-user token may now be missing. Clear in-memory state
    /// first so lingering data from the previous profile doesn't bleed through.
    public func handleForegroundTransition() {
        let previousServerCount = savedServers.count
        let wasAuthenticated = isAuthenticated

        // Clear in-memory state before reloading from the (possibly new user's) keychain.
        savedServers = []
        sharedServerConfigs = []
        savedSeerrServers = []
        currentServer = nil
        seerrServer = nil
        isAuthenticated = false

        loadFromStorage()

        if previousServerCount > 0, savedServers.isEmpty {
            needsTVOSUserOnboarding = true
        } else if wasAuthenticated, !isAuthenticated {
            // Same shared configs but the per-user token is gone → new profile
            needsTVOSUserOnboarding = true
        } else if savedServers.isEmpty {
            needsTVOSUserOnboarding = true
        }
    }

    // MARK: - Quick-Connect Hints (shared App Group)

    public var lastServerURL: URL? {
        sharedDefaults.url(forKey: lastServerURLKey)
    }

    public var lastSeerrURL: URL? {
        sharedDefaults.url(forKey: lastSeerrURLKey)
    }

    public var lastSeerrAuthMode: SeerrAuthMode? {
        guard let raw = sharedDefaults.string(forKey: lastSeerrAuthModeKey) else { return nil }
        return SeerrAuthMode(rawValue: raw)
    }

    private func recordLastServerURL(_ url: URL) {
        sharedDefaults.set(url, forKey: lastServerURLKey)
    }

    private func recordLastSeerr(url: URL, mode: SeerrAuthMode) {
        sharedDefaults.set(url, forKey: lastSeerrURLKey)
        sharedDefaults.set(mode.rawValue, forKey: lastSeerrAuthModeKey)
    }

    // MARK: - Bootstrap

    /// Call once on app launch (in .task on RootView).
    public func loadFromStorage() {
        loadSharedServerConfigs() // always — needed for tvOS onboarding check
        loadSeerrServers()

        // Resolve the server to restore. Prefer the explicit active id from
        // per-user defaults, but fall back to the first saved server that has
        // a valid token in the per-user Keychain. The fallback covers cases
        // where the active id was lost (e.g. UserDefaults.standard wiped on a
        // tvOS profile reset) but the config + token are still present.
        let activeId = UserDefaults.standard.string(forKey: activeServerIdKey)
        let resolvedServer: JellyfinServer? = {
            if let id = activeId,
               let s = sharedServerConfigs.first(where: { $0.id == id }),
               KeychainManager.exists(key: "jellyfin_token_\(s.id)")
            {
                return s
            }
            return sharedServerConfigs.first(where: {
                KeychainManager.exists(key: "jellyfin_token_\($0.id)")
            })
        }()

        if let server = resolvedServer {
            currentServer = server
            savedServers = sharedServerConfigs
            isAuthenticated = true
            // Persist the resolved id so subsequent launches use the fast path.
            if activeId != server.id {
                UserDefaults.standard.set(server.id, forKey: activeServerIdKey)
            }
        } else {
            currentServer = nil
            isAuthenticated = false
        }

        // Restore active Seerr server
        if let seerrId = UserDefaults.standard.string(forKey: activeSeerrIdKey),
           let server = savedSeerrServers.first(where: { $0.id == seerrId })
        {
            seerrServer = server
        } else {
            seerrServer = savedSeerrServers.first
        }
    }

    /// Call after loadFromStorage — determines if tvOS onboarding sheet is needed.
    public func checkTVOSUserOnboarding() {
        #if os(tvOS)
            // If there are shared server configs but this profile has no token → onboard
            if !sharedServerConfigs.isEmpty, !isAuthenticated {
                needsTVOSUserOnboarding = true
            }
        #endif
    }

    // MARK: - Shared Config Loading (all tvOS profiles)

    private func loadSharedServerConfigs() {
        let ids = sharedDefaults.stringArray(forKey: "shared_server_ids") ?? []
        let loaded = ids.compactMap { try? KeychainManager.loadServerConfig(id: $0) }
        // Dedupe by baseURL — guards against stale stored IDs that resolve to the
        // same server (e.g. after a failed-then-retried sign-in).
        sharedServerConfigs = loaded.reduce(into: [JellyfinServer]()) { result, server in
            if !result.contains(where: { $0.baseURL == server.baseURL }) {
                result.append(server)
            }
        }
        savedServers = sharedServerConfigs
    }

    private func loadSeerrServers() {
        let ids = sharedDefaults.stringArray(forKey: "shared_seerr_ids") ?? []
        let loaded = ids.compactMap { try? KeychainManager.loadSeerrConfig(id: $0) }
        savedSeerrServers = loaded.reduce(into: [SeerrServer]()) { result, server in
            if !result.contains(where: { $0.baseURL == server.baseURL }) {
                result.append(server)
            }
        }
    }

    // MARK: - Server Management

    /// Add a new Jellyfin server. Config goes to shared Keychain; token per-user.
    /// If a server with the same baseURL already exists, replace it instead of
    /// appending — this prevents duplicate entries after a failed-then-retried
    /// sign-in or a tvOS profile switch.
    public func addServer(_ server: JellyfinServer, token: String) throws {
        // Config (URL, name) → device-wide shared Keychain
        try KeychainManager.saveServerConfig(server)
        // Token → per-user Keychain (only after success)
        try KeychainManager.saveServerToken(token, for: server.id)

        // Register server ID in shared App Group defaults so other profiles find it
        var ids = sharedDefaults.stringArray(forKey: "shared_server_ids") ?? []
        if !ids.contains(server.id) {
            ids.append(server.id)
            sharedDefaults.set(ids, forKey: "shared_server_ids")
        }

        if let idx = savedServers.firstIndex(where: { $0.baseURL == server.baseURL }) {
            savedServers[idx] = server
        } else {
            savedServers.append(server)
        }
        if let idx = sharedServerConfigs.firstIndex(where: { $0.baseURL == server.baseURL }) {
            sharedServerConfigs[idx] = server
        } else {
            sharedServerConfigs.append(server)
        }
        recordLastServerURL(server.baseURL)
        setActiveServer(server)
    }

    public func removeServer(_ server: JellyfinServer) {
        try? KeychainManager.deleteServerToken(for: server.id)
        try? KeychainManager.deleteServerConfig(id: server.id)
        savedServers.removeAll { $0.id == server.id }
        sharedServerConfigs.removeAll { $0.id == server.id }

        var ids = sharedDefaults.stringArray(forKey: "shared_server_ids") ?? []
        ids.removeAll { $0 == server.id }
        sharedDefaults.set(ids, forKey: "shared_server_ids")

        if currentServer?.id == server.id {
            currentServer = savedServers.first
            isAuthenticated = currentServer.map {
                KeychainManager.exists(key: "jellyfin_token_\($0.id)")
            } ?? false
        }
    }

    /// Convenience method for completing a login flow — stores the token and
    /// sets the server as active. Safe to call from any platform.
    public func completeLogin(server: JellyfinServer, token: String) {
        try? addServer(server, token: token)
        needsTVOSUserOnboarding = false
    }

    /// Called from the onboarding wizard's final step. Clears any onboarding
    /// flags so the router transitions to the main app.
    public func completeOnboarding() {
        needsTVOSUserOnboarding = false
        isOnboarding = false
    }

    public func setActiveServer(_ server: JellyfinServer) {
        currentServer = server
        isAuthenticated = KeychainManager.exists(key: "jellyfin_token_\(server.id)")
        UserDefaults.standard.set(server.id, forKey: activeServerIdKey)
    }

    public func tokenForCurrentServer() -> String? {
        guard let server = currentServer else { return nil }
        return try? KeychainManager.loadServerToken(for: server.id)
    }

    // MARK: - Seerr Server Management

    /// Add a Seerr server. Config + API key → shared Keychain. Sessions → per-user.
    public func addSeerrServer(_ server: SeerrServer, apiKey: String) throws {
        var srv = server
        srv.authMode = .apiKey
        try KeychainManager.saveSeerrConfig(srv)
        try KeychainManager.saveSeerrApiKey(apiKey, for: srv.id)
        registerSeerrServer(srv)
    }

    /// Add a Seerr server that authenticates via session cookie (Jellyfin or local account).
    /// Config → shared Keychain. Session cookie → per-user Keychain.
    public func addSeerrServer(_ server: SeerrServer, sessionCookie: String, authMode: SeerrAuthMode) throws {
        var srv = server
        srv.authMode = authMode
        try KeychainManager.saveSeerrConfig(srv)
        try KeychainManager.saveSeerrSession(sessionCookie, for: srv.id)
        registerSeerrServer(srv)
    }

    private func registerSeerrServer(_ server: SeerrServer) {
        var ids = sharedDefaults.stringArray(forKey: "shared_seerr_ids") ?? []
        if !ids.contains(server.id) {
            ids.append(server.id)
            sharedDefaults.set(ids, forKey: "shared_seerr_ids")
        }

        if let idx = savedSeerrServers.firstIndex(where: { $0.baseURL == server.baseURL }) {
            savedSeerrServers[idx] = server
        } else {
            savedSeerrServers.append(server)
        }
        recordLastSeerr(url: server.baseURL, mode: server.authMode)
        setActiveSeerrServer(server)
    }

    public func removeSeerrServer(_ server: SeerrServer) {
        try? KeychainManager.deleteSeerrApiKey(for: server.id)
        try? KeychainManager.deleteSeerrSession(for: server.id)
        savedSeerrServers.removeAll { $0.id == server.id }

        var ids = sharedDefaults.stringArray(forKey: "shared_seerr_ids") ?? []
        ids.removeAll { $0 == server.id }
        sharedDefaults.set(ids, forKey: "shared_seerr_ids")

        if seerrServer?.id == server.id {
            seerrServer = savedSeerrServers.first
        }
    }

    public func setActiveSeerrServer(_ server: SeerrServer) {
        seerrServer = server
        UserDefaults.standard.set(server.id, forKey: activeSeerrIdKey)
    }

    /// Resolves the correct credential for the current user and auth mode.
    public func credentialForCurrentSeerrServer() -> SeerrCredential? {
        guard let server = seerrServer else { return nil }
        return SeerrAPIClient.shared.credential(for: server)
    }

    public var hasSeerrConfigured: Bool {
        guard let server = seerrServer else { return false }
        return server.isAuthenticatedForCurrentUser()
    }

    // MARK: - tvOS Seerr Onboarding

    /// Determines what (if anything) the new tvOS user needs to do for Seerr.
    /// Marked async so it can be awaited from tvOS login flow (currently synchronous
    /// but async keyword future-proofs against session verification needs).
    public func seerrOnboardingNeeded() async -> SeerrOnboardingResult {
        guard let seerr = seerrServer else { return .notNeeded }
        guard !seerr.isAuthenticatedForCurrentUser() else { return .notNeeded }

        switch seerr.authMode {
        case .apiKey:
            // API key is device-wide — no per-user action needed
            return .notNeeded
        case .jellyfinCredentials:
            return .needsJellyfinAuth(seerr)
        case .localAccount:
            return .needsLocalCredentials(seerr)
        }
    }

    /// Called after a successful Jellyfin login when Seerr uses Jellyfin auth.
    /// Silently authenticates the current user against Seerr with the same creds.
    /// Non-fatal — failure is swallowed so it doesn't block playback.
    public func autoAuthSeerr(username: String, password: String) async {
        guard let seerr = seerrServer,
              seerr.authMode == .jellyfinCredentials else { return }
        do {
            // Convenience overload automatically saves session cookie to per-user Keychain
            try await SeerrAPIClient.shared.authenticateWithJellyfin(
                seerrServer: seerr,
                username: username,
                password: password
            )
        } catch {
            // Non-fatal: Discover tab will surface a "reconnect" prompt when needed
        }
    }

    // MARK: - Sign Out

    public func signOut() {
        guard let server = currentServer else { return }
        try? KeychainManager.deleteServerToken(for: server.id)
        // Also invalidate Seerr session for this user
        if let seerr = seerrServer {
            try? KeychainManager.deleteSeerrSession(for: seerr.id)
        }
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: activeServerIdKey)
    }

    public func signOutAll() {
        // Remove per-user tokens only — keep shared server configs for other profiles
        for server in savedServers {
            try? KeychainManager.deleteServerToken(for: server.id)
        }
        if let seerr = seerrServer {
            try? KeychainManager.deleteSeerrSession(for: seerr.id)
        }
        currentServer = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: activeServerIdKey)
    }

    /// Nuclear option — removes everything including shared configs.
    /// Only use from an admin action; other tvOS profiles will lose server discovery.
    public func removeAllDataIncludingShared() {
        signOutAll()
        for server in savedServers {
            try? KeychainManager.deleteServerConfig(id: server.id)
        }
        if let seerr = seerrServer {
            try? KeychainManager.deleteSeerrApiKey(for: seerr.id)
        }
        savedServers = []
        savedSeerrServers = []
        sharedServerConfigs = []
        seerrServer = nil
        sharedDefaults.removeObject(forKey: "shared_server_ids")
        sharedDefaults.removeObject(forKey: "shared_seerr_ids")
    }
}

// MARK: - SeerrOnboardingResult

public enum SeerrOnboardingResult: Equatable, Sendable {
    /// No Seerr configured, already authenticated, or API key (device-wide — no per-user action needed).
    case notNeeded
    /// Seerr uses Jellyfin credentials — prompt the user for their Jellyfin password.
    case needsJellyfinAuth(SeerrServer)
    /// Seerr uses local accounts — prompt the user for their Seerr email + password.
    case needsLocalCredentials(SeerrServer)

    public static func == (lhs: SeerrOnboardingResult, rhs: SeerrOnboardingResult) -> Bool {
        switch (lhs, rhs) {
        case (.notNeeded, .notNeeded): true
        case let (.needsJellyfinAuth(a), .needsJellyfinAuth(b)): a.id == b.id
        case let (.needsLocalCredentials(a), .needsLocalCredentials(b)): a.id == b.id
        default: false
        }
    }
}
