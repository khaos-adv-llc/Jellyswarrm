// MARK: - AppState.swift

// Jellyswarrm — GPL v3 with App Store exception
//
// tvOS multi-user strategy:
//   "Runs as Current User" entitlement → OS re-launches app per tvOS profile.
//   Shared storage  (App Group UserDefaults + shared Keychain) → server IDs, server configs, Seerr configs, API keys.
//   Per-user storage (regular Keychain + standard UserDefaults)  → Jellyfin tokens, Seerr session cookies.
//
// On launch AppState checks: shared configs exist but no per-user token → needsTVOSUserOnboarding = true.

import Foundation
import Observation

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

    /// Server configs readable from shared storage — populated before per-user auth.
    public var sharedServerConfigs: [JellyfinServer] = []

    // MARK: - UserDefaults Keys

    // Standard UserDefaults are per-user on tvOS with "Runs as Current User".
    // App Group UserDefaults are device-wide (shared between profiles).

    private let activeServerIdKey = "jellyswarrm_active_server_id"
    private let activeSeerrIdKey = "jellyswarrm_active_seerr_server_id"
    private let serverIdsKey = "jellyswarrm_server_ids"
    private let seerrServerIdsKey = "jellyswarrm_seerr_server_ids"

    /// App Group suite — device-wide, readable by all tvOS profiles.
    /// Must match the App Group entitlement: com.jellyswarrm.shared
    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: "group.com.jellyswarrm.shared") ?? .standard
    }

    public init() {}

    // MARK: - Bootstrap

    /// Call once on app launch (in .task on RootView).
    public func loadFromStorage() {
        loadSharedServerConfigs() // always — needed for tvOS onboarding check
        loadSeerrServers()

        // Restore active server from per-user defaults
        if let activeId = UserDefaults.standard.string(forKey: activeServerIdKey),
           let server = sharedServerConfigs.first(where: { $0.id == activeId })
        {
            currentServer = server
            savedServers = sharedServerConfigs
            isAuthenticated = KeychainManager.exists(key: "jellyfin_token_\(server.id)")
        }

        // Restore active Seerr server
        if let seerrId = UserDefaults.standard.string(forKey: activeSeerrIdKey),
           let server = savedSeerrServers.first(where: { $0.id == seerrId })
        {
            seerrServer = server
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
        sharedServerConfigs = ids.compactMap { try? KeychainManager.loadServerConfig(id: $0) }
        savedServers = sharedServerConfigs
    }

    private func loadSeerrServers() {
        let ids = sharedDefaults.stringArray(forKey: "shared_seerr_ids") ?? []
        savedSeerrServers = ids.compactMap { try? KeychainManager.loadSeerrConfig(id: $0) }
    }

    // MARK: - Server Management

    /// Add a new Jellyfin server. Config goes to shared Keychain; token per-user.
    public func addServer(_ server: JellyfinServer, token: String) throws {
        // Config (URL, name) → device-wide shared Keychain
        try KeychainManager.saveServerConfig(server)
        // Token → per-user Keychain
        try KeychainManager.saveServerToken(token, for: server.id)

        // Register server ID in shared App Group defaults so other profiles find it
        var ids = sharedDefaults.stringArray(forKey: "shared_server_ids") ?? []
        if !ids.contains(server.id) {
            ids.append(server.id)
            sharedDefaults.set(ids, forKey: "shared_server_ids")
        }

        if !savedServers.contains(where: { $0.id == server.id }) {
            savedServers.append(server)
            sharedServerConfigs.append(server)
        }
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
        try KeychainManager.saveSeerrConfig(server)
        try KeychainManager.saveSeerrApiKey(apiKey, for: server.id)

        var ids = sharedDefaults.stringArray(forKey: "shared_seerr_ids") ?? []
        if !ids.contains(server.id) {
            ids.append(server.id)
            sharedDefaults.set(ids, forKey: "shared_seerr_ids")
        }

        if !savedSeerrServers.contains(where: { $0.id == server.id }) {
            savedSeerrServers.append(server)
        }
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

    public enum SeerrOnboardingResult: Equatable {
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
