// MARK: - ProfileManager.swift

// Jellyswarrm — LGPL-2.1-or-later
//
// Manages multiple Jellyfin user profiles with Keychain-backed token storage.
// On tvOS with "Runs as Current User" entitlement, each system user gets
// their own sandboxed UserDefaults and Keychain — no manual separation needed.

import Foundation
import Observation

@MainActor
@Observable
public final class ProfileManager {
    public static let shared = ProfileManager()

    private let defaults: UserDefaults
    private let profilesKey = "storedProfiles_v2"
    private let activeProfileKey = "activeProfileId_v2"
    private let profileTokenKeyPrefix = "jellyswarrm_profile_token_"

    public private(set) var profiles: [JellyfinProfile] = []
    public private(set) var activeProfile: JellyfinProfile?

    public init(suiteName: String = "group.com.jellyswarrm.shared") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        load()
    }

    // MARK: - Public API

    public func addProfile(_ profile: JellyfinProfile) {
        try? KeychainManager.save(key: profileTokenKeyPrefix + profile.id, value: profile.accessToken)
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        save()
        setActive(profile)
    }

    public func removeProfile(id: String) {
        try? KeychainManager.delete(key: profileTokenKeyPrefix + id)
        profiles.removeAll { $0.id == id }
        save()
        if activeProfile?.id == id {
            activeProfile = profiles.first
            defaults.set(activeProfile?.id, forKey: activeProfileKey)
        }
    }

    public func setActive(_ profile: JellyfinProfile) {
        var updated = profile
        updated.lastUsed = Date()
        if let idx = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[idx] = updated
        }
        activeProfile = updated
        defaults.set(updated.id, forKey: activeProfileKey)
        save()
    }

    public func setAutoSignIn(_ enabled: Bool, for profileId: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[idx].autoSignIn = enabled
        save()
    }

    public func token(for profileId: String) -> String? {
        try? KeychainManager.load(key: profileTokenKeyPrefix + profileId)
    }

    /// Returns true if we should skip the profile picker (auto sign-in).
    public var shouldAutoSignIn: Bool {
        if profiles.count == 1 { return true }
        return profiles.filter { $0.autoSignIn }.count == 1
    }

    public var autoSignInProfile: JellyfinProfile? {
        if profiles.count == 1 { return profiles.first }
        return profiles.first { $0.autoSignIn }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: profilesKey),
              let decoded = try? JSONDecoder().decode([JellyfinProfile].self, from: data)
        else { return }
        profiles = decoded
        if let activeId = defaults.string(forKey: activeProfileKey) {
            activeProfile = profiles.first { $0.id == activeId }
        } else {
            activeProfile = profiles.first
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
    }
}
