// MARK: - KeychainManager.swift

// Jellyswarrm — GPL v3 with App Store exception
//
// Security model:
//   Per-user Keychain  → Jellyfin tokens, Seerr session cookies
//   Shared Keychain    → Server configs (URL/name), Seerr API keys
//
// On tvOS with "Runs as Current User" entitlement the OS automatically isolates
// the per-user Keychain per Apple TV profile. The shared Keychain uses
// kSecAttrAccessibleAlwaysThisDeviceOnly so all profiles can read server config.

import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case duplicateItem
    case invalidData
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound: "Credential not found in Keychain."
        case .duplicateItem: "Credential already exists."
        case .invalidData: "Stored credential data is invalid."
        case let .unexpectedStatus(s): "Keychain error (OSStatus \(s))."
        }
    }
}

public enum KeychainManager {
    // MARK: - Constants

    private static let service = "com.jellyswarrm.app"
    private static let sharedService = "com.jellyswarrm.app.shared"

    // MARK: - Per-user Keychain (default, isolated per tvOS profile)

    public static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }
        try? delete(key: key)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public static func load(key: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let str = String(data: data, encoding: .utf8)
            else {
                throw KeychainError.invalidData
            }
            return str
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public static func delete(key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public static func exists(key: String) -> Bool {
        (try? load(key: key)) != nil
    }

    // MARK: - Shared Keychain (visible to all tvOS profiles on this device)

    //
    // tvOS 16+: kSecAttrAccessibleAlwaysThisDeviceOnly combined with
    // NOT opting into data-protection keychain makes items user-independent.
    // On iOS/macOS there is only one user per process, so shared == regular.

    public static func saveShared(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }
        try? deleteShared(key: key)
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: sharedService,
            kSecAttrAccount: key,
            kSecValueData: data,
            // Always-accessible so any tvOS profile can read server config
            kSecAttrAccessible: kSecAttrAccessibleAlwaysThisDeviceOnly,
        ]
        #if os(tvOS)
            // Opt out of per-user data protection so the item is device-wide
            query[kSecUseDataProtectionKeychain] = false
        #endif
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public static func loadShared(key: String) throws -> String {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: sharedService,
            kSecAttrAccount: key,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]
        #if os(tvOS)
            query[kSecUseDataProtectionKeychain] = false
        #endif
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let str = String(data: data, encoding: .utf8)
            else {
                throw KeychainError.invalidData
            }
            return str
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public static func deleteShared(key: String) throws {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: sharedService,
            kSecAttrAccount: key,
        ]
        #if os(tvOS)
            query[kSecUseDataProtectionKeychain] = false
        #endif
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public static func existsShared(key: String) -> Bool {
        (try? loadShared(key: key)) != nil
    }

    // MARK: - Jellyfin Convenience (per-user tokens)

    public static func saveServerToken(_ token: String, for serverId: String) throws {
        try save(key: "jellyfin_token_\(serverId)", value: token)
    }

    public static func loadServerToken(for serverId: String) throws -> String {
        try load(key: "jellyfin_token_\(serverId)")
    }

    public static func deleteServerToken(for serverId: String) throws {
        try delete(key: "jellyfin_token_\(serverId)")
    }

    // MARK: - Jellyfin Server Config (shared — all tvOS profiles can discover)

    public static func saveServerConfig(_ server: JellyfinServer) throws {
        let data = try JSONEncoder().encode(server)
        guard let str = String(data: data, encoding: .utf8) else { throw KeychainError.invalidData }
        try saveShared(key: "server_config_\(server.id)", value: str)
    }

    public static func loadServerConfig(id: String) throws -> JellyfinServer {
        let str = try loadShared(key: "server_config_\(id)")
        guard let data = str.data(using: .utf8) else { throw KeychainError.invalidData }
        return try JSONDecoder().decode(JellyfinServer.self, from: data)
    }

    public static func deleteServerConfig(id: String) throws {
        try deleteShared(key: "server_config_\(id)")
    }

    // MARK: - Seerr API Key (shared — device-level, all profiles use the same key)

    public static func saveSeerrApiKey(_ apiKey: String, for seerrId: String) throws {
        try saveShared(key: "seerr_apikey_\(seerrId)", value: apiKey)
    }

    public static func loadSeerrApiKey(for seerrId: String) throws -> String {
        try loadShared(key: "seerr_apikey_\(seerrId)")
    }

    public static func deleteSeerrApiKey(for seerrId: String) throws {
        try deleteShared(key: "seerr_apikey_\(seerrId)")
    }

    // MARK: - Seerr Server Config (shared)

    public static func saveSeerrConfig(_ server: SeerrServer) throws {
        let data = try JSONEncoder().encode(server)
        guard let str = String(data: data, encoding: .utf8) else { throw KeychainError.invalidData }
        try saveShared(key: "seerr_config_\(server.id)", value: str)
    }

    public static func loadSeerrConfig(id: String) throws -> SeerrServer {
        let str = try loadShared(key: "seerr_config_\(id)")
        guard let data = str.data(using: .utf8) else { throw KeychainError.invalidData }
        return try JSONDecoder().decode(SeerrServer.self, from: data)
    }

    // MARK: - Seerr Session Cookie (per-user — isolated per tvOS profile)

    public static func saveSeerrSession(_ cookie: String, for seerrId: String) throws {
        try save(key: "seerr_session_\(seerrId)", value: cookie)
    }

    public static func loadSeerrSession(for seerrId: String) throws -> String {
        try load(key: "seerr_session_\(seerrId)")
    }

    public static func deleteSeerrSession(for seerrId: String) throws {
        try delete(key: "seerr_session_\(seerrId)")
    }

    public static func hasSeerrSession(for seerrId: String) -> Bool {
        exists(key: "seerr_session_\(seerrId)")
    }

    // MARK: - Stable device ID (shared — same across all tvOS profiles)

    public static var deviceId: String {
        let key = "jellyswarrm_device_id"
        if let existing = try? loadShared(key: key) { return existing }
        let newId = UUID().uuidString
        try? saveShared(key: key, value: newId)
        return newId
    }
}
