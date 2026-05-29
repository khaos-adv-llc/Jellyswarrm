// MARK: - JellyfinProfile.swift

// Jellyswarrm — LGPL-2.1-or-later
//
// A stored Jellyfin user profile on this device. The access token is held
// in the per-user Keychain (see KeychainManager) — never persisted in this
// struct's Codable representation.

import Foundation

public struct JellyfinProfile: Codable, Identifiable, Equatable, Sendable, Hashable {
    public let id: String
    public let serverURL: String
    public let serverName: String
    public let username: String
    public let accessToken: String
    public var avatarURL: String?
    public var autoSignIn: Bool
    public var lastUsed: Date

    public init(
        id: String,
        serverURL: String,
        serverName: String,
        username: String,
        accessToken: String,
        avatarURL: String? = nil,
        autoSignIn: Bool = false,
        lastUsed: Date = Date()
    ) {
        self.id = id
        self.serverURL = serverURL
        self.serverName = serverName
        self.username = username
        self.accessToken = accessToken
        self.avatarURL = avatarURL
        self.autoSignIn = autoSignIn
        self.lastUsed = lastUsed
    }

    private enum CodingKeys: String, CodingKey {
        case id, serverURL, serverName, username, avatarURL, autoSignIn, lastUsed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.serverURL = try c.decode(String.self, forKey: .serverURL)
        self.serverName = try c.decode(String.self, forKey: .serverName)
        self.username = try c.decode(String.self, forKey: .username)
        self.avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL)
        self.autoSignIn = try c.decodeIfPresent(Bool.self, forKey: .autoSignIn) ?? false
        self.lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed) ?? Date()
        self.accessToken = ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(serverURL, forKey: .serverURL)
        try c.encode(serverName, forKey: .serverName)
        try c.encode(username, forKey: .username)
        try c.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try c.encode(autoSignIn, forKey: .autoSignIn)
        try c.encode(lastUsed, forKey: .lastUsed)
    }

    public func withToken(_ token: String) -> JellyfinProfile {
        JellyfinProfile(
            id: id,
            serverURL: serverURL,
            serverName: serverName,
            username: username,
            accessToken: token,
            avatarURL: avatarURL,
            autoSignIn: autoSignIn,
            lastUsed: lastUsed
        )
    }
}
