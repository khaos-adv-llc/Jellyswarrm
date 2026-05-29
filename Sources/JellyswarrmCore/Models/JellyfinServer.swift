// MARK: - JellyfinServer.swift

// Jellyswarrm — LGPL-2.1-or-later

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

    /// Builds the Authorization header value for API requests.
    /// Values are sanitized — Jellyfin rejects (HTTP 400) headers containing
    /// unescaped quotes, control characters, or non-ASCII bytes. macOS device
    /// names from Host.current().localizedName commonly contain apostrophes
    /// ("Alice's MacBook") which would otherwise break the quoted value.
    public func authorizationHeader(token: String, deviceId: String, deviceName: String, appVersion: String) -> String {
        let client = AuthHeaderValue.sanitize("Jellyswarrm-\(AuthHeaderValue.platformSuffix)")
        let device = AuthHeaderValue.sanitize(deviceName)
        let id = AuthHeaderValue.sanitize(deviceId)
        let version = AuthHeaderValue.sanitize(appVersion)
        let tok = AuthHeaderValue.sanitize(token)
        return "MediaBrowser Client=\"\(client)\", Device=\"\(device)\", DeviceId=\"\(id)\", Version=\"\(version)\", Token=\"\(tok)\""
    }
}

/// Helpers for building Jellyfin's X-Emby-Authorization header.
enum AuthHeaderValue {
    /// Strip characters that break the quoted header format: quotes, commas,
    /// control bytes, and any non-ASCII. Result is a safe ASCII slug.
    static func sanitize(_ raw: String) -> String {
        let stripped = raw.unicodeScalars.compactMap { scalar -> Character? in
            guard scalar.isASCII else { return nil }
            let v = scalar.value
            if v < 0x20 || v == 0x7F { return nil }
            if scalar == "\"" || scalar == "," || scalar == "\\" { return nil }
            return Character(scalar)
        }
        let result = String(stripped).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "Device" : result
    }

    static var platformSuffix: String {
        #if os(iOS)
            return "iOS"
        #elseif os(macOS)
            return "macOS"
        #elseif os(tvOS)
            return "tvOS"
        #elseif os(visionOS)
            return "visionOS"
        #else
            return "Apple"
        #endif
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
