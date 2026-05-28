// MARK: - JellyfinServer.swift

// Jellyswarrm — GPL v3 with App Store exception

import Foundation

/// Represents a configured Jellyfin server connection.
/// Credentials (token) are stored in Keychain — never in this struct directly.
public struct JellyfinServer: Sendable, Identifiable, Equatable, Hashable, Codable {
    public let id: String
    public var name: String
    public var baseURL: URL
    public var userId: String
    public var username: String

    // Token is NOT stored here — retrieved from Keychain at runtime
    public var keychainTokenKey: String {
        "jellyfin_token_\(id)"
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: URL,
        userId: String,
        username: String
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.userId = userId
        self.username = username
    }

    /// Builds the Authorization header value for API requests
    public func authorizationHeader(token: String, deviceId: String, deviceName: String, appVersion: String) -> String {
        "MediaBrowser Client=\"Jellyswarrm\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(appVersion)\", Token=\"\(token)\""
    }
}

/// Represents a configured Seerr server.
/// API key is stored in Keychain.
public struct SeerrServer: Sendable, Identifiable, Equatable, Hashable, Codable {
    public let id: String
    public var name: String
    public var baseURL: URL

    public var keychainApiKeyKey: String {
        "seerr_apikey_\(id)"
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: URL
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }
}
