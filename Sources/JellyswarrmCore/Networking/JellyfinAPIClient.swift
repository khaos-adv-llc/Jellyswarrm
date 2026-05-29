// MARK: - JellyfinAPIClient.swift

// Jellyswarrm — LGPL-2.1-or-later

import Foundation
#if os(macOS)
    import AppKit
#endif

/// Thread-safe Jellyfin API client using Swift concurrency
public actor JellyfinAPIClient {
    public static let shared = JellyfinAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Content-Type": "application/json",
        ]
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(string)"
            )
        }
    }

    // MARK: - Auth

    public func authenticate(
        serverURL: URL,
        username: String,
        password: String,
        deviceId: String,
        deviceName: String,
        appVersion: String
    ) async throws -> AuthResponse {
        let url = serverURL.appendingPathComponent("/Users/AuthenticateByName")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            preAuthHeader(deviceId: deviceId, deviceName: deviceName, appVersion: appVersion),
            forHTTPHeaderField: "X-Emby-Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["Username": username, "Pw": password]
        request.httpBody = try JSONEncoder().encode(body)

        return try await perform(request: request)
    }

    // MARK: - Library

    public func getLibrarySections(
        server: JellyfinServer,
        token: String
    ) async throws -> [LibrarySection] {
        let url = server.baseURL
            .appendingPathComponent("/Users/\(server.userId)/Views")
        let request = makeRequest(url: url, server: server, token: token)
        let response: ItemsResponse<LibrarySection> = try await perform(request: request)
        return response.items
    }

    public func getItems(
        server: JellyfinServer,
        token: String,
        parentId: String? = nil,
        sortBy: String = "SortName",
        sortOrder: String = "Ascending",
        filters: [String] = [],
        fields: [String] = ["Overview", "Genres", "MediaStreams", "People", "Studios", "ImageTags", "BackdropImageTags"],
        limit: Int = 50,
        startIndex: Int = 0,
        recursive: Bool = false,
        includeItemTypes: [String] = []
    ) async throws -> ItemsResponse<MediaItem> {
        var components = URLComponents(
            url: server.baseURL.appendingPathComponent("/Users/\(server.userId)/Items"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems = [
            URLQueryItem(name: "SortBy", value: sortBy),
            URLQueryItem(name: "SortOrder", value: sortOrder),
            URLQueryItem(name: "Fields", value: fields.joined(separator: ",")),
            URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "StartIndex", value: "\(startIndex)"),
            URLQueryItem(name: "Recursive", value: recursive ? "true" : "false"),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb,Logo"),
        ]
        if let parentId { queryItems.append(URLQueryItem(name: "ParentId", value: parentId)) }
        if !filters.isEmpty { queryItems.append(URLQueryItem(name: "Filters", value: filters.joined(separator: ","))) }
        if !includeItemTypes.isEmpty { queryItems.append(URLQueryItem(
            name: "IncludeItemTypes",
            value: includeItemTypes.joined(separator: ",")
        )) }
        components.queryItems = queryItems

        guard let url = components.url else { throw NetworkError.invalidURL }
        let request = makeRequest(url: url, server: server, token: token)
        return try await perform(request: request)
    }

    public func getContinueWatching(
        server: JellyfinServer,
        token: String,
        limit: Int = 12
    ) async throws -> [MediaItem] {
        var components = URLComponents(
            url: server.baseURL.appendingPathComponent("/Users/\(server.userId)/Items/Resume"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "Fields", value: "Overview,MediaStreams,UserData,ImageTags,BackdropImageTags"),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true"),
        ]
        guard let url = components.url else { throw NetworkError.invalidURL }
        let request = makeRequest(url: url, server: server, token: token)
        let response: ItemsResponse<MediaItem> = try await perform(request: request)
        return response.items
    }

    public func getNextUp(
        server: JellyfinServer,
        token: String,
        limit: Int = 12
    ) async throws -> [MediaItem] {
        var components = URLComponents(
            url: server.baseURL.appendingPathComponent("/Shows/NextUp"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "UserId", value: server.userId),
            URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "Fields", value: "Overview,MediaStreams,UserData,ImageTags,BackdropImageTags"),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true"),
        ]
        guard let url = components.url else { throw NetworkError.invalidURL }
        let request = makeRequest(url: url, server: server, token: token)
        let response: ItemsResponse<MediaItem> = try await perform(request: request)
        return response.items
    }

    public func getSeasons(
        server: JellyfinServer,
        token: String,
        seriesId: String
    ) async throws -> [MediaItem] {
        var components = URLComponents(
            url: server.baseURL.appendingPathComponent("/Shows/\(seriesId)/Seasons"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "UserId", value: server.userId),
            URLQueryItem(name: "Fields", value: "Overview,ImageTags,BackdropImageTags"),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb"),
        ]
        guard let url = components.url else { throw NetworkError.invalidURL }
        let request = makeRequest(url: url, server: server, token: token)
        let response: ItemsResponse<MediaItem> = try await perform(request: request)
        return response.items
    }

    public func getEpisodes(
        server: JellyfinServer,
        token: String,
        seriesId: String,
        seasonId: String? = nil
    ) async throws -> [MediaItem] {
        var components = URLComponents(
            url: server.baseURL.appendingPathComponent("/Shows/\(seriesId)/Episodes"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems = [
            URLQueryItem(name: "UserId", value: server.userId),
            URLQueryItem(name: "Fields", value: "Overview,MediaStreams,ImageTags,BackdropImageTags"),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb"),
        ]
        if let seasonId { queryItems.append(URLQueryItem(name: "SeasonId", value: seasonId)) }
        components.queryItems = queryItems
        guard let url = components.url else { throw NetworkError.invalidURL }
        let request = makeRequest(url: url, server: server, token: token)
        let response: ItemsResponse<MediaItem> = try await perform(request: request)
        return response.items
    }

    public func getItemDetail(
        server: JellyfinServer,
        token: String,
        itemId: String
    ) async throws -> MediaItem {
        var components = URLComponents(
            url: server.baseURL.appendingPathComponent("/Users/\(server.userId)/Items/\(itemId)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "Fields", value: "Overview,Genres,MediaStreams,People,Studios,Taglines,ProviderIds,ImageTags,BackdropImageTags,Chapters"),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true"),
        ]
        guard let url = components.url else { throw NetworkError.invalidURL }
        let request = makeRequest(url: url, server: server, token: token)
        return try await perform(request: request)
    }

    public func getPlaybackInfo(
        server: JellyfinServer,
        token: String,
        itemId: String,
        mediaSourceId: String? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil
    ) async throws -> PlaybackInfo {
        var components = URLComponents(
            url: server.baseURL.appendingPathComponent("/Items/\(itemId)/PlaybackInfo"),
            resolvingAgainstBaseURL: false
        )!
        // UserId must be a query param for Jellyfin to populate stream URLs
        components.queryItems = [
            URLQueryItem(name: "UserId", value: server.userId),
        ]
        guard let url = components.url else { throw NetworkError.invalidURL }
        var request = makeRequest(url: url, server: server, token: token)
        request.httpMethod = "POST"
        var body: [String: Any] = [
            "UserId": server.userId,
            "DeviceProfile": defaultDeviceProfile(),
            "AutoOpenLiveStream": true,
            "IsPlayback": true,
        ]
        if let mediaSourceId { body["MediaSourceId"] = mediaSourceId }
        if let audioStreamIndex { body["AudioStreamIndex"] = audioStreamIndex }
        if let subtitleStreamIndex { body["SubtitleStreamIndex"] = subtitleStreamIndex }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // DEBUG: log raw response so we can inspect stream URLs. The first
        // call (no mediaSourceId) discovers available sources; the second
        // resolves stream URLs for a chosen source. Tag each so the double
        // log is readable.
        let raw = try await rawPerform(request: request)
        if let json = String(data: raw, encoding: .utf8) {
            let tag = mediaSourceId == nil ? "[PlaybackInfo sources]" : "[PlaybackInfo raw]"
            print("\(tag) \(json.prefix(2000))")
        }
        return try decoder.decode(PlaybackInfo.self, from: raw)
    }

    public func searchItems(
        server: JellyfinServer,
        token: String,
        query: String,
        limit: Int = 30
    ) async throws -> [MediaItem] {
        var components = URLComponents(
            url: server.baseURL.appendingPathComponent("/Users/\(server.userId)/Items"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "SearchTerm", value: query),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series,Episode"),
            URLQueryItem(name: "Fields", value: "Overview,MediaStreams,UserData,ImageTags,BackdropImageTags"),
            URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true"),
        ]
        guard let url = components.url else { throw NetworkError.invalidURL }
        let request = makeRequest(url: url, server: server, token: token)
        let response: ItemsResponse<MediaItem> = try await perform(request: request)
        return response.items
    }

    // MARK: - Playback Reporting

    public func reportPlaybackStart(
        server: JellyfinServer,
        token: String,
        itemId: String,
        positionTicks: Int64,
        mediaSourceId: String,
        playSessionId: String?,
        playMethod: String = "Transcode",
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?
    ) async throws {
        let url = server.baseURL.appendingPathComponent("/Sessions/Playing")
        var request = makeRequest(url: url, server: server, token: token)
        request.httpMethod = "POST"
        var body: [String: Any] = [
            "ItemId": itemId,
            "PositionTicks": positionTicks,
            "MediaSourceId": mediaSourceId,
            "CanSeek": true,
            "IsPaused": false,
            "IsMuted": false,
            "PlayMethod": playMethod,
        ]
        if let playSessionId { body["PlaySessionId"] = playSessionId }
        if let a = audioStreamIndex { body["AudioStreamIndex"] = a }
        if let s = subtitleStreamIndex { body["SubtitleStreamIndex"] = s }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await rawPerform(request: request)
    }

    public func reportPlaybackProgress(
        server: JellyfinServer,
        token: String,
        itemId: String,
        positionTicks: Int64,
        isPaused: Bool,
        mediaSourceId: String,
        playSessionId: String?,
        playMethod: String = "Transcode"
    ) async throws {
        let url = server.baseURL.appendingPathComponent("/Sessions/Playing/Progress")
        var request = makeRequest(url: url, server: server, token: token)
        request.httpMethod = "POST"
        var body: [String: Any] = [
            "ItemId": itemId,
            "PositionTicks": positionTicks,
            "IsPaused": isPaused,
            "IsMuted": false,
            "CanSeek": true,
            "MediaSourceId": mediaSourceId,
            "PlayMethod": playMethod,
            "EventName": "timeupdate",
        ]
        if let playSessionId { body["PlaySessionId"] = playSessionId }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await rawPerform(request: request)
    }

    public func reportPlaybackStopped(
        server: JellyfinServer,
        token: String,
        itemId: String,
        positionTicks: Int64,
        mediaSourceId: String,
        playSessionId: String?,
        playMethod: String = "Transcode"
    ) async throws {
        let url = server.baseURL.appendingPathComponent("/Sessions/Playing/Stopped")
        var request = makeRequest(url: url, server: server, token: token)
        request.httpMethod = "POST"
        var body: [String: Any] = [
            "ItemId": itemId,
            "PositionTicks": positionTicks,
            "MediaSourceId": mediaSourceId,
            "PlayMethod": playMethod,
        ]
        if let playSessionId { body["PlaySessionId"] = playSessionId }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await rawPerform(request: request)
    }

    public func markPlayed(
        server: JellyfinServer,
        token: String,
        itemId: String
    ) async throws -> UserData {
        let url = server.baseURL
            .appendingPathComponent("/Users/\(server.userId)/PlayedItems/\(itemId)")
        var request = makeRequest(url: url, server: server, token: token)
        request.httpMethod = "POST"
        return try await perform(request: request)
    }

    public func markUnplayed(
        server: JellyfinServer,
        token: String,
        itemId: String
    ) async throws -> UserData {
        let url = server.baseURL
            .appendingPathComponent("/Users/\(server.userId)/PlayedItems/\(itemId)")
        var request = makeRequest(url: url, server: server, token: token)
        request.httpMethod = "DELETE"
        return try await perform(request: request)
    }

    // MARK: - Quick Connect

    /// Initiates a Quick Connect session on the server.
    /// Returns a `QuickConnectState` with the 6-digit `code` to display to the user.
    public func initiateQuickConnect(
        serverURL: URL,
        deviceId: String,
        deviceName: String,
        appVersion: String
    ) async throws -> QuickConnectState {
        let url = serverURL.appendingPathComponent("/QuickConnect/Initiate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Quick Connect initiation requires the MediaBrowser header but NO token
        request.setValue(
            preAuthHeader(deviceId: deviceId, deviceName: deviceName, appVersion: appVersion),
            forHTTPHeaderField: "X-Emby-Authorization"
        )
        return try await perform(request: request)
    }

    /// Polls the server to check whether the Quick Connect code has been approved.
    /// Call every ~5 seconds until `state.authenticated == true`.
    public func checkQuickConnect(
        serverURL: URL,
        secret: String,
        deviceId: String,
        deviceName: String,
        appVersion: String
    ) async throws -> QuickConnectState {
        var components = URLComponents(
            url: serverURL.appendingPathComponent("/QuickConnect/Connect"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "Secret", value: secret)]
        guard let url = components.url else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            preAuthHeader(deviceId: deviceId, deviceName: deviceName, appVersion: appVersion),
            forHTTPHeaderField: "X-Emby-Authorization"
        )
        return try await perform(request: request)
    }

    /// Exchanges an authenticated Quick Connect secret for a full user token.
    /// Only call after `checkQuickConnect` returns `authenticated == true`.
    public func authenticateWithQuickConnect(
        serverURL: URL,
        secret: String,
        deviceId: String,
        deviceName: String,
        appVersion: String
    ) async throws -> AuthResponse {
        let url = serverURL.appendingPathComponent("/Users/AuthenticateWithQuickConnect")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            preAuthHeader(deviceId: deviceId, deviceName: deviceName, appVersion: appVersion),
            forHTTPHeaderField: "X-Emby-Authorization"
        )
        let body = ["Secret": secret]
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request: request)
    }

    // MARK: - Jellyswarrm Plugin Discovery

    /// Probe the server for the Jellyswarrm plugin's published config.
    /// Returns nil if the plugin is not installed, the endpoint is unreachable,
    /// or the response can't be decoded. Uses a short timeout so a missing
    /// plugin never blocks the login flow.
    public nonisolated func discoverJellyswarrmPlugin(serverURL: URL) async -> PluginConfig? {
        let url = serverURL.appendingPathComponent("/Plugins/Jellyswarrm/Config")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(PluginConfig.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Image URL Builder

    public nonisolated func imageURL(
        server: JellyfinServer,
        itemId: String,
        imageType: ImageType,
        tag: String? = nil,
        maxWidth: Int = 400
    ) -> URL {
        var components = URLComponents(
            url: server.baseURL.appendingPathComponent("/Items/\(itemId)/Images/\(imageType.rawValue)"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems = [URLQueryItem(name: "maxWidth", value: "\(maxWidth)")]
        if let tag { queryItems.append(URLQueryItem(name: "tag", value: tag)) }
        queryItems.append(URLQueryItem(name: "quality", value: "90"))
        components.queryItems = queryItems
        return components.url ?? server.baseURL
    }

    // MARK: - Private Helpers

    /// Builds an X-Emby-Authorization header value with no token (used for
    /// authentication endpoints and Quick Connect). Values are sanitized so
    /// non-ASCII / quoted characters in macOS device names can't break the
    /// header and trigger a 400 from Jellyfin.
    private nonisolated func preAuthHeader(deviceId: String, deviceName: String, appVersion: String) -> String {
        let client = AuthHeaderValue.sanitize("Jellyswarrm-\(AuthHeaderValue.platformSuffix)")
        let device = AuthHeaderValue.sanitize(deviceName)
        let id = AuthHeaderValue.sanitize(deviceId)
        let version = AuthHeaderValue.sanitize(appVersion)
        return "MediaBrowser Client=\"\(client)\", Device=\"\(device)\", DeviceId=\"\(id)\", Version=\"\(version)\""
    }

    private func makeRequest(url: URL, server: JellyfinServer, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let deviceId = UIDeviceHelper.deviceId
        let deviceName = UIDeviceHelper.deviceName
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        request.setValue(
            server.authorizationHeader(
                token: token,
                deviceId: deviceId,
                deviceName: deviceName,
                appVersion: appVersion
            ),
            forHTTPHeaderField: "X-Emby-Authorization"
        )
        return request
    }

    private func perform<T: Decodable>(request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.networkUnavailable
        }
        if let error = NetworkError.from(statusCode: http.statusCode) {
            throw error
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error.localizedDescription)
        }
    }

    private func rawPerform(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.networkUnavailable
        }
        if let error = NetworkError.from(statusCode: http.statusCode) {
            throw error
        }
        return data
    }

    private func defaultDeviceProfile() -> [String: Any] {
        // Capabilities-driven device profile. Direct play whatever the hardware
        // decoder supports — HEVC, Dolby Vision, AV1 — so the server never has
        // to transcode on Apple Silicon / A-series chips.

        var directPlayProfiles: [[String: Any]] = []
        var codecProfiles: [[String: Any]] = []

        // H.264 — universally supported on every Apple device we care about.
        directPlayProfiles.append([
            "Type": "Video",
            "Container": "mp4,mkv,mov,m4v",
            "VideoCodec": "h264",
            "AudioCodec": "aac,mp3,ac3,eac3,flac,opus,dts,truehd,pcm",
        ])

        // HEVC / H.265 — hardware decoded on A9+. Add Dolby Vision profiles
        // (dvhe = profile 5, dvh1 = profile 8) when the chip can do DV in HW.
        if PlaybackCapabilities.supportsHEVC {
            var hevcVideoCodecs = "hevc,h265"
            if PlaybackCapabilities.supportsDolbyVision {
                hevcVideoCodecs += ",dvhe,dvh1"
            }
            directPlayProfiles.append([
                "Type": "Video",
                "Container": "mp4,mkv,mov,m4v",
                "VideoCodec": hevcVideoCodecs,
                "AudioCodec": "aac,ac3,eac3,truehd,dts,flac,opus,pcm,aac-latm,mp3",
            ])
        }

        // AV1 — A17 Pro / M-series have hardware decoders.
        if PlaybackCapabilities.supportsAV1 {
            directPlayProfiles.append([
                "Type": "Video",
                "Container": "mp4,mkv,webm",
                "VideoCodec": "av1",
                "AudioCodec": "aac,opus,flac",
            ])
        }

        // Audio-only direct play
        directPlayProfiles.append([
            "Type": "Audio",
            "Container": "mp3,aac,flac,ogg,opus,m4a,wav",
            "AudioCodec": "mp3,aac,flac,opus,vorbis,pcm",
        ])

        // HEVC level/width caps so we don't accept beyond-spec streams.
        if PlaybackCapabilities.supportsHEVC {
            codecProfiles.append([
                "Type": "Video",
                "Codec": "hevc",
                "Conditions": [
                    ["Condition": "LessThanEqual", "Property": "VideoLevel", "Value": "183", "IsRequired": false],
                    ["Condition": "LessThanEqual", "Property": "Width", "Value": "3840", "IsRequired": false],
                ],
            ])
        }

        // Transcode fallback — HLS / H.264 for anything we can't direct play.
        let transcodingProfiles: [[String: Any]] = [[
            "Type": "Video",
            "Container": "ts",
            "VideoCodec": "h264",
            "AudioCodec": "aac,mp3",
            "Protocol": "hls",
            "Context": "Streaming",
            "MinSegments": 2,
            "BreakOnNonKeyFrames": true,
            "MaxAudioChannels": "8",
        ]]

        let subtitleProfiles: [[String: Any]] = [
            ["Format": "srt", "Method": "External"],
            ["Format": "ass", "Method": "External"],
            ["Format": "ssa", "Method": "External"],
            ["Format": "vtt", "Method": "External"],
            ["Format": "sub", "Method": "Embed"],
            ["Format": "pgs", "Method": "Embed"],
            ["Format": "pgssub", "Method": "Embed"],
            ["Format": "dvdsub", "Method": "Embed"],
            ["Format": "dvbsub", "Method": "Embed"],
        ]

        return [
            "DirectPlayProfiles": directPlayProfiles,
            "TranscodingProfiles": transcodingProfiles,
            "CodecProfiles": codecProfiles,
            "SubtitleProfiles": subtitleProfiles,
            "ResponseProfiles": [],
            "MaxStaticBitrate": 200_000_000,
            "MaxStreamingBitrate": 200_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,
        ]
    }
}

// MARK: - Device Info Helper

public enum UIDeviceHelper {
    public static var deviceId: String {
        // Stable per-device identifier using Keychain
        let key = "jellyswarrm_device_id"
        if let existing = try? KeychainManager.load(key: key) {
            return existing
        }
        let newId = UUID().uuidString
        try? KeychainManager.save(key: key, value: newId)
        return newId
    }

    public static var deviceName: String {
        // UIDevice.current is @MainActor-isolated, so we use ProcessInfo/Host
        // instead — both are safe to call from any concurrency context.
        #if os(iOS) || os(tvOS)
            return ProcessInfo.processInfo.hostName
        #elseif os(macOS)
            return Host.current().localizedName ?? "Mac"
        #else
            return "Jellyswarrm Device"
        #endif
    }
}

// MARK: - Jellyswarrm Plugin Config

/// Response payload from `GET /Plugins/Jellyswarrm/Config`. The plugin
/// publishes the server admin's preferred Overseerr/Jellyseerr URL and
/// (optionally) an API key for shared access.
public struct PluginConfig: Codable, Sendable {
    public let overseerrUrl: String
    public let overseerrApiKey: String

    public init(overseerrUrl: String, overseerrApiKey: String) {
        self.overseerrUrl = overseerrUrl
        self.overseerrApiKey = overseerrApiKey
    }

    private enum CodingKeys: String, CodingKey {
        case overseerrUrl = "OverseerrUrl"
        case overseerrApiKey = "OverseerrApiKey"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.overseerrUrl = (try? c.decode(String.self, forKey: .overseerrUrl)) ?? ""
        self.overseerrApiKey = (try? c.decode(String.self, forKey: .overseerrApiKey)) ?? ""
    }
}

// MARK: - Quick Connect State

/// Response model for `/QuickConnect/Initiate` and `/QuickConnect/Connect`.
public struct QuickConnectState: Codable, Sendable {
    /// The internal secret used to poll and exchange for a token.
    /// Keep this private — never display it to the user.
    public let secret: String

    /// The short human-readable code shown to the user (e.g. "123456").
    /// Display this in the UI so the user can enter it in another Jellyfin client.
    public let code: String

    /// Whether the code has been approved in another Jellyfin client.
    /// Poll `checkQuickConnect` every 5 seconds until this is `true`.
    public let authenticated: Bool

    enum CodingKeys: String, CodingKey {
        case secret = "Secret"
        case code = "Code"
        case authenticated = "Authenticated"
    }
}
