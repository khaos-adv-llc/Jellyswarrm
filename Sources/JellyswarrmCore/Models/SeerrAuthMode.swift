// MARK: - SeerrAuthMode.swift
// Jellyswarrm — GPL v3 with App Store exception
//
// Tracks how each Seerr server expects users to authenticate.
// This determines the per-user onboarding flow on tvOS when a new profile
// switches in: Jellyfin creds auto-carry over, API key is already shared,
// local accounts need their own login.

import Foundation

public enum SeerrAuthMode: String, Codable, Sendable, CaseIterable {

    /// Admin-level API key.
    /// Stored in the device-wide shared Keychain — works for every tvOS profile
    /// automatically with no additional sign-in required.
    case apiKey

    /// Authenticate via Jellyfin username + password.
    /// POST /api/v1/auth/jellyfin — returns a session cookie stored per-user.
    /// On tvOS profile switch: silently re-auth using the new user's Jellyfin creds,
    /// or prompt for password if only Quick Connect was used.
    case jellyfinCredentials

    /// Local Seerr account (email + password, independent of Jellyfin).
    /// POST /api/v1/auth/local — returns a session cookie stored per-user.
    /// On tvOS profile switch: always prompts for this user's Seerr credentials.
    case localAccount

    public var displayName: String {
        switch self {
        case .apiKey:               return "API Key"
        case .jellyfinCredentials:  return "Jellyfin Account"
        case .localAccount:         return "Local Seerr Account"
        }
    }

    public var requiresPerUserAuth: Bool {
        switch self {
        case .apiKey:               return false
        case .jellyfinCredentials:  return true
        case .localAccount:         return true
        }
    }
}

// MARK: - SeerrServer extension

extension SeerrServer {

    /// Non-sensitive — stored in UserDefaults, not Keychain.
    /// The UserDefaults key is per-device (not per tvOS user), matching the
    /// server config which is also device-wide.
    public var authMode: SeerrAuthMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "seerr_authmode_\(id)") ?? ""
            return SeerrAuthMode(rawValue: raw) ?? .apiKey
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "seerr_authmode_\(id)")
        }
    }

    /// True when this profile's session is valid (or API key is present — always true)
    public func isAuthenticatedForCurrentUser() -> Bool {
        switch authMode {
        case .apiKey:
            return KeychainManager.existsShared(key: "seerr_apikey_\(id)")
        case .jellyfinCredentials, .localAccount:
            return KeychainManager.hasSeerrSession(for: id)
        }
    }
}
