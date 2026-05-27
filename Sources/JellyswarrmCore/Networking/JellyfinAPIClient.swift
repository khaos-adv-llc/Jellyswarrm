// MARK: - JellyfinAPIClient.swift
// Jellyswarrm — GPL v3 with App Store exception

import Foundation

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
            "Content-Type": "application/json"
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
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Cannot decode date: \(string)")
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
            "MediaBrowser Client=\"Jellyswarrm\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(appVersion)\"",
            forHTTPHeaderField: "X-Emby-Authorization"
        )

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
        fields: [String] = ["Overview", "Genres", "MediaStreams", "People", "Studios"],
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
        if !includeItemTypes.isEmpty { queryItems.append(URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes.joined(separator: ","))) }
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
            URLQueryItem(name: "Fields", value: "Overview,MediaStreams,UserData"),
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
            URLQueryItem(name: "Fields", value: "Overview,MediaStreams,UserData"),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true"),
        ]
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
            URLQueryItem(name: "Fields", value: "Overview,Genres,MediaStreams,People,Studios,Taglines,ProviderIds"),
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
        itemId: String
    ) async throws -> PlaybackInfo {
        let url = server.baseURL.appendingPathComponent("/Items/\(itemId)/PlaybackInfo")
        var request = makeRequest(url: url, server: server, token: token)
        request.httpMethod = "POST"
        let body: [String: Any] = [
            "UserId": server.userId,
            "DeviceProfile": defaultDeviceProfile()
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request: request)
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
            URLQueryItem(name: "Fields", value: "Overview,MediaStreams,UserData"),
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
        ]
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
        mediaSourceId: String
    ) async throws {
        let url = server.baseURL.appendingPathComponent("/Sessions/Playing/Progress")
        var request = makeRequest(url: url, server: server, token: token)
        request.httpMethod = "POST"
        let body: [String: Any] = [
            "ItemId": itemId,
            "PositionTicks": positionTicks,
            "IsPaused": isPaused,
            "MediaSourceId": mediaSourceId,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await rawPerform(request: request)
    }

    public func reportPlaybackStopped(
        server: JellyfinServer,
        token: String,
        itemId: String,
        positionTicks: Int64,
        mediaSourceId: String
    ) async throws {
        let url = server.baseURL.appendingPathComponent("/Sessions/Playing/Stopped")
        var request = makeRequest(url: url, server: server, token: token)
        request.httpMethod = "POST"
        let body: [String: Any] = [
            "ItemId": itemId,
            "PositionTicks": positionTicks,
            "MediaSourceId": mediaSourceId,
        ]
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
            "MediaBrowser Client=\"Jellyswarrm\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(appVersion)\"",
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
            "MediaBrowser Client=\"Jellyswarrm\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(appVersion)\"",
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
            "MediaBrowser Client=\"Jellyswarrm\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(appVersion)\"",
            forHTTPHeaderField: "X-Emby-Authorization"
        )
        let body = ["Secret": secret]
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request: request)
    }

    // MARK: - Image URL Builder

    public func imageURL(
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

    private func makeRequest(url: URL, server: JellyfinServer, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let deviceId = UIDeviceHelper.deviceId
        let deviceName = UIDeviceHelper.deviceName
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        request.setValue(
            server.authorizationHeader(token: token, deviceId: deviceId, deviceName: deviceName, appVersion: appVersion),
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
        // A broad device profile that allows direct play for common formats
        // and falls back to transcode for everything else
        return [
            "MaxStaticBitrate": 140_000_000,
            "MaxStreamingBitrate": 140_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,
            "DirectPlayProfiles": [
                ["Container": "mp4,m4v", "Type": "Video"],
                ["Container": "mov", "Type": "Video"],
                ["Container": "mkv", "Type": "Video"],
                ["Container": "mp3", "Type": "Audio"],
                ["Container": "aac", "Type": "Audio"],
                ["Container": "flac", "Type": "Audio"],
            ],
            "TranscodingProfiles": [
                [
                    "Container": "ts",
                    "Type": "Video",
                    "AudioCodec": "aac",
                    "VideoCodec": "h264",
                    "Protocol": "hls",
                    "Context": "Streaming",
                    "MaxAudioChannels": "6",
                    "MinSegments": "2",
                    "BreakOnNonKeyFrames": true,
                ]
            ],
            "ContainerProfiles": [],
            "CodecProfiles": [],
            "SubtitleProfiles": [
                ["Format": "srt", "Method": "External"],
                ["Format": "vtt", "Method": "External"],
                ["Format": "ass", "Method": "External"],
                ["Format": "ssa", "Method": "External"],
            ]
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
        #if os(iOS) || os(tvOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Jellyswarrm Device"
        #endif
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
