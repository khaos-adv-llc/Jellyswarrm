// MARK: - JellyfinSDKClient.swift

// Jellyswarrm — LGPL-2.1-or-later
//
// Thin wrapper around the official Jellyfin Swift SDK. Holds a per-server SDK
// `JellyfinClient` keyed by server id and exposes typed helpers for the
// endpoints we have migrated off the hand-rolled `JellyfinAPIClient`.
//
// The SDK's `JellyfinClient` is `@unchecked Sendable` (it mutates `accessToken`
// internally). We confine all access through this actor so Swift 6 strict
// concurrency stays happy.

import Foundation
import JellyfinAPI

public actor JellyfinSDKClient {
    public static let shared = JellyfinSDKClient()

    private var clients: [String: JellyfinAPI.JellyfinClient] = [:]

    public init() {}

    // MARK: - Configuration

    /// Build (or replace) the SDK client for a given server. Safe to call
    /// repeatedly — replaces any existing client for the same id.
    public func configure(server: JellyfinServer, token: String) {
        let deviceId = UIDeviceHelper.deviceId
        let deviceName = UIDeviceHelper.deviceName
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let config = JellyfinAPI.JellyfinClient.Configuration(
            url: server.baseURL,
            accessToken: token,
            client: "Jellyswarrm-\(AuthHeaderValue.platformSuffix)",
            deviceName: AuthHeaderValue.sanitize(deviceName),
            deviceID: AuthHeaderValue.sanitize(deviceId),
            version: appVersion
        )
        clients[server.id] = JellyfinAPI.JellyfinClient(configuration: config)
    }

    private func client(for server: JellyfinServer, token: String) -> JellyfinAPI.JellyfinClient {
        if let existing = clients[server.id], existing.accessToken == token {
            return existing
        }
        configure(server: server, token: token)
        return clients[server.id]! // just configured
    }

    // MARK: - Playback Reporting (MIGRATED TO SDK)

    public func reportPlaybackStart(
        server: JellyfinServer,
        token: String,
        itemId: String,
        positionTicks: Int64,
        mediaSourceId: String,
        playSessionId: String?,
        playMethod: PlayMethod,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?
    ) async throws {
        let c = client(for: server, token: token)
        var info = PlaybackStateInfo()
        info.itemID = itemId
        info.mediaSourceID = mediaSourceId
        info.positionTicks = Int(positionTicks)
        info.playSessionID = playSessionId
        info.playMethod = playMethod
        info.canSeek = true
        info.isPaused = false
        info.isMuted = false
        info.audioStreamIndex = audioStreamIndex
        info.subtitleStreamIndex = subtitleStreamIndex
        let request = Paths.reportPlaybackStart(info)
        _ = try await c.send(request)
    }

    public func reportPlaybackProgress(
        server: JellyfinServer,
        token: String,
        itemId: String,
        positionTicks: Int64,
        isPaused: Bool,
        mediaSourceId: String,
        playSessionId: String?,
        playMethod: PlayMethod
    ) async throws {
        let c = client(for: server, token: token)
        var info = PlaybackStateInfo()
        info.itemID = itemId
        info.mediaSourceID = mediaSourceId
        info.positionTicks = Int(positionTicks)
        info.playSessionID = playSessionId
        info.playMethod = playMethod
        info.canSeek = true
        info.isPaused = isPaused
        info.isMuted = false
        let request = Paths.reportPlaybackProgress(info)
        _ = try await c.send(request)
    }

    public func reportPlaybackStopped(
        server: JellyfinServer,
        token: String,
        itemId: String,
        positionTicks: Int64,
        mediaSourceId: String,
        playSessionId: String?
    ) async throws {
        let c = client(for: server, token: token)
        var info = PlaybackStopInfo()
        info.itemID = itemId
        info.mediaSourceID = mediaSourceId
        info.positionTicks = Int(positionTicks)
        info.playSessionID = playSessionId
        let request = Paths.reportPlaybackStopped(info)
        _ = try await c.send(request)
    }

    // MARK: - Item / UserData (MIGRATED TO SDK)

    /// Reads `UserData.PlaybackPositionTicks` directly from the item detail
    /// endpoint via the SDK. Returns 0 if no resume position is recorded.
    public func resumeTicks(
        server: JellyfinServer,
        token: String,
        itemId: String
    ) async throws -> Int64 {
        let c = client(for: server, token: token)
        let request = Paths.getItem(itemID: itemId, userID: server.userId)
        let response = try await c.send(request)
        return Int64(response.value.userData?.playbackPositionTicks ?? 0)
    }
}
