// MARK: - SeerrAPIClient.swift

// Jellyswarrm — LGPL-2.1-or-later

import Foundation

/// Thread-safe Seerr API client.
///
/// Auth modes:
///   - API key   → pass via X-Api-Key header (device-wide, shared Keychain)
///   - Session   → pass via Cookie header (per-user, isolated Keychain)
///
/// The client is auth-mode agnostic: callers decide which credential to pass.
/// AppState resolves the right credential for the current user before calling.
public actor SeerrAPIClient {
    public static let shared = SeerrAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        // We manage the session cookie manually via Keychain — opt out of automatic
        // cookie handling so HTTPCookieStorage doesn't strip Set-Cookie from responses.
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Authentication

    /// Test server reachability and validate the API key.
    ///
    /// 1. GET /api/v1/settings/public (no auth) — verifies the URL points at a Seerr instance.
    /// 2. GET /api/v1/auth/me with X-Api-Key — validates that the API key works.
    ///
    /// Returns the authenticated user so the UI can confirm which account the key belongs to.
    @discardableResult
    public func testConnection(baseURL: URL, apiKey: String) async throws -> SeerrUser {
        let publicURL = baseURL.appendingPathComponent("/api/v1/settings/public")
        var publicRequest = URLRequest(url: publicURL)
        publicRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let _: SeerrPublicSettings = try await performLogging(request: publicRequest, label: "settings/public")

        let meURL = baseURL.appendingPathComponent("/api/v1/auth/me")
        let meRequest = makeRequest(url: meURL, apiKey: apiKey)
        return try await performLogging(request: meRequest, label: "auth/me")
    }

    /// Authenticate using Jellyfin username + password.
    /// Returns the session cookie value (`connect.sid=<value>`) to store in the per-user Keychain.
    public func authenticateWithJellyfin(
        baseURL: URL,
        username: String,
        password: String
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("/api/v1/auth/jellyfin")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["username": username, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.networkUnavailable }
        if let error = NetworkError.from(statusCode: http.statusCode) { throw error }

        return try extractSessionCookie(from: http, url: url)
    }

    /// Authenticate using a local Seerr account (email + password).
    /// Returns the session cookie value (`connect.sid=<value>`) to store in the per-user Keychain.
    public func authenticateWithLocalAccount(
        baseURL: URL,
        email: String,
        password: String
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("/api/v1/auth/local")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.networkUnavailable }
        if let error = NetworkError.from(statusCode: http.statusCode) { throw error }

        return try extractSessionCookie(from: http, url: url)
    }

    /// Parse the Set-Cookie response header(s) and return `connect.sid=<value>` suitable
    /// for use as a Cookie request header. Falls back to the first session-like cookie if
    /// the server uses a different name.
    private func extractSessionCookie(from http: HTTPURLResponse, url: URL) throws -> String {
        let setCookie = http.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        let headers: [String: String] = setCookie.isEmpty ? [:] : ["Set-Cookie": setCookie]
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        let candidate = parsed.first(where: { $0.name == "connect.sid" })
            ?? parsed.first(where: { $0.name.lowercased().contains("session") })
            ?? parsed.first
        if let cookie = candidate, !cookie.value.isEmpty {
            return "\(cookie.name)=\(cookie.value)"
        }
        throw NetworkError.custom("Seerr did not return a session cookie. Check your credentials.")
    }

    // MARK: - SeerrServer convenience overloads

    // These accept a SeerrServer directly and automatically persist the session
    // cookie to the per-user Keychain after a successful authentication.

    /// Authenticate with a SeerrServer using Jellyfin credentials.
    /// Persists the resulting session cookie to the per-user Keychain automatically.
    @discardableResult
    public func authenticateWithJellyfin(
        seerrServer: SeerrServer,
        username: String,
        password: String
    ) async throws -> String {
        let cookie = try await authenticateWithJellyfin(
            baseURL: seerrServer.baseURL,
            username: username,
            password: password
        )
        try KeychainManager.saveSeerrSession(cookie, for: seerrServer.id)
        return cookie
    }

    /// Authenticate with a SeerrServer using a local account (email + password).
    /// Persists the resulting session cookie to the per-user Keychain automatically.
    @discardableResult
    public func authenticateWithLocalAccount(
        seerrServer: SeerrServer,
        email: String,
        password: String
    ) async throws -> String {
        let cookie = try await authenticateWithLocalAccount(
            baseURL: seerrServer.baseURL,
            email: email,
            password: password
        )
        try KeychainManager.saveSeerrSession(cookie, for: seerrServer.id)
        return cookie
    }

    /// Verify a session cookie is still valid. Returns the current user on success.
    public func verifySession(baseURL: URL, sessionCookie: String) async throws -> SeerrUser {
        let url = baseURL.appendingPathComponent("/api/v1/auth/me")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        return try await perform(request: request)
    }

    /// Sign out and invalidate the session on the server.
    public func signOut(baseURL: URL, sessionCookie: String) async throws {
        let url = baseURL.appendingPathComponent("/api/v1/auth/logout")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        _ = try await rawPerform(request: request)
    }

    // MARK: - Credential resolution helper

    /// Build auth headers for either API key or session mode.
    /// AppState calls this after resolving which credential the current user has.
    public nonisolated func credential(for server: SeerrServer) -> SeerrCredential? {
        switch server.authMode {
        case .apiKey:
            guard let key = try? KeychainManager.loadSeerrApiKey(for: server.id) else { return nil }
            return .apiKey(key)
        case .jellyfinCredentials, .localAccount:
            guard let cookie = try? KeychainManager.loadSeerrSession(for: server.id) else { return nil }
            return .session(cookie)
        }
    }

    // MARK: - Discover

    public func discoverTrending(
        baseURL: URL, credential: SeerrCredential, page: Int = 1
    ) async throws -> SeerrPage<SeerrSearchResult> {
        let url = buildURL(base: baseURL, path: "/api/v1/discover/trending", query: ["page": "\(page)"])
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func discoverMovies(
        baseURL: URL, credential: SeerrCredential, page: Int = 1, genre: Int? = nil, language: String? = nil
    ) async throws -> SeerrPage<SeerrMovieResult> {
        var params = ["page": "\(page)"]
        if let g = genre { params["genre"] = "\(g)" }
        if let l = language { params["language"] = l }
        let url = buildURL(base: baseURL, path: "/api/v1/discover/movies", query: params)
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func discoverMoviesUpcoming(
        baseURL: URL, credential: SeerrCredential, page: Int = 1
    ) async throws -> SeerrPage<SeerrMovieResult> {
        let url = buildURL(base: baseURL, path: "/api/v1/discover/movies/upcoming", query: ["page": "\(page)"])
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func discoverTV(
        baseURL: URL, credential: SeerrCredential, page: Int = 1, genre: Int? = nil, network: Int? = nil
    ) async throws -> SeerrPage<SeerrTvResult> {
        var params = ["page": "\(page)"]
        if let g = genre { params["genre"] = "\(g)" }
        if let n = network { params["network"] = "\(n)" }
        let url = buildURL(base: baseURL, path: "/api/v1/discover/tv", query: params)
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func discoverTVUpcoming(
        baseURL: URL, credential: SeerrCredential, page: Int = 1
    ) async throws -> SeerrPage<SeerrTvResult> {
        let url = buildURL(base: baseURL, path: "/api/v1/discover/tv/upcoming", query: ["page": "\(page)"])
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func discoverTrending(
        baseURL: URL,
        apiKey: String,
        page: Int = 1
    ) async throws -> SeerrPage<SeerrSearchResult> {
        try await discoverTrending(baseURL: baseURL, credential: .apiKey(apiKey), page: page)
    }

    public func discoverMovies(
        baseURL: URL,
        apiKey: String,
        page: Int = 1,
        genre: Int? = nil,
        language: String? = nil
    ) async throws -> SeerrPage<SeerrMovieResult> {
        try await discoverMovies(
            baseURL: baseURL,
            credential: .apiKey(apiKey),
            page: page,
            genre: genre,
            language: language
        )
    }

    public func discoverMoviesUpcoming(
        baseURL: URL,
        apiKey: String,
        page: Int = 1
    ) async throws -> SeerrPage<SeerrMovieResult> {
        try await discoverMoviesUpcoming(baseURL: baseURL, credential: .apiKey(apiKey), page: page)
    }

    public func discoverTV(
        baseURL: URL,
        apiKey: String,
        page: Int = 1,
        genre: Int? = nil,
        network: Int? = nil
    ) async throws -> SeerrPage<SeerrTvResult> {
        try await discoverTV(baseURL: baseURL, credential: .apiKey(apiKey), page: page, genre: genre, network: network)
    }

    public func discoverTVUpcoming(
        baseURL: URL,
        apiKey: String,
        page: Int = 1
    ) async throws -> SeerrPage<SeerrTvResult> {
        try await discoverTVUpcoming(baseURL: baseURL, credential: .apiKey(apiKey), page: page)
    }

    // MARK: - Detail

    public func getMovieDetails(
        baseURL: URL,
        credential: SeerrCredential,
        movieId: Int
    ) async throws -> SeerrMovieResult {
        let url = baseURL.appendingPathComponent("/api/v1/movie/\(movieId)")
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func getTVDetails(baseURL: URL, credential: SeerrCredential, tvId: Int) async throws -> SeerrTvResult {
        let url = baseURL.appendingPathComponent("/api/v1/tv/\(tvId)")
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func getMovieRecommendations(
        baseURL: URL,
        credential: SeerrCredential,
        movieId: Int,
        page: Int = 1
    ) async throws -> SeerrPage<SeerrMovieResult> {
        let url = buildURL(base: baseURL, path: "/api/v1/movie/\(movieId)/recommendations", query: ["page": "\(page)"])
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func getTVRecommendations(
        baseURL: URL,
        credential: SeerrCredential,
        tvId: Int,
        page: Int = 1
    ) async throws -> SeerrPage<SeerrTvResult> {
        let url = buildURL(base: baseURL, path: "/api/v1/tv/\(tvId)/recommendations", query: ["page": "\(page)"])
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    // MARK: - Search

    public func search(
        baseURL: URL,
        credential: SeerrCredential,
        query: String,
        page: Int = 1
    ) async throws -> SeerrPage<SeerrSearchResult> {
        let url = buildURL(base: baseURL, path: "/api/v1/search", query: ["query": query, "page": "\(page)"])
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func search(
        baseURL: URL,
        apiKey: String,
        query: String,
        page: Int = 1
    ) async throws -> SeerrPage<SeerrSearchResult> {
        try await search(baseURL: baseURL, credential: .apiKey(apiKey), query: query, page: page)
    }

    // MARK: - Requests

    public func createRequest(
        baseURL: URL,
        credential: SeerrCredential,
        request req: RequestCreate
    ) async throws -> MediaRequest {
        let url = baseURL.appendingPathComponent("/api/v1/request")
        var request = makeRequest(url: url, credential: credential)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(req)
        return try await perform(request: request)
    }

    public func getRequests(
        baseURL: URL,
        credential: SeerrCredential,
        filter: String? = nil,
        sort: String = "added",
        page: Int = 1
    ) async throws -> SeerrPage<MediaRequest> {
        var params: [String: String] = ["sort": sort, "page": "\(page)"]
        if let f = filter { params["filter"] = f }
        let url = buildURL(base: baseURL, path: "/api/v1/request", query: params)
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func cancelRequest(baseURL: URL, credential: SeerrCredential, requestId: Int) async throws {
        let url = baseURL.appendingPathComponent("/api/v1/request/\(requestId)")
        var request = makeRequest(url: url, credential: credential)
        request.httpMethod = "DELETE"
        _ = try await rawPerform(request: request)
    }

    // MARK: - Genres

    public func getMovieGenres(baseURL: URL, credential: SeerrCredential) async throws -> [SeerrGenre] {
        try await perform(request: makeRequest(
            url: baseURL.appendingPathComponent("/api/v1/genres/movie"),
            credential: credential
        ))
    }

    public func getTVGenres(baseURL: URL, credential: SeerrCredential) async throws -> [SeerrGenre] {
        try await perform(request: makeRequest(
            url: baseURL.appendingPathComponent("/api/v1/genres/tv"),
            credential: credential
        ))
    }

    public func getMovieGenres(baseURL: URL, apiKey: String) async throws -> [SeerrGenre] {
        try await getMovieGenres(baseURL: baseURL, credential: .apiKey(apiKey))
    }

    public func getTVGenres(baseURL: URL, apiKey: String) async throws -> [SeerrGenre] {
        try await getTVGenres(baseURL: baseURL, credential: .apiKey(apiKey))
    }

    // MARK: - Service (Radarr/Sonarr) Configuration

    public func getRadarrServers(
        baseURL: URL,
        credential: SeerrCredential
    ) async throws -> [SeerrServiceServer] {
        let url = baseURL.appendingPathComponent("/api/v1/service/radarr")
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func getRadarrProfiles(
        baseURL: URL,
        serverId: Int,
        credential: SeerrCredential
    ) async throws -> SeerrServiceDetail {
        let url = baseURL.appendingPathComponent("/api/v1/service/radarr/\(serverId)")
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func getSonarrServers(
        baseURL: URL,
        credential: SeerrCredential
    ) async throws -> [SeerrServiceServer] {
        let url = baseURL.appendingPathComponent("/api/v1/service/sonarr")
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    public func getSonarrProfiles(
        baseURL: URL,
        serverId: Int,
        credential: SeerrCredential
    ) async throws -> SeerrServiceDetail {
        let url = baseURL.appendingPathComponent("/api/v1/service/sonarr/\(serverId)")
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    // MARK: - Current User / Public Settings

    /// Get the currently authenticated user (for permission checks).
    public func getCurrentUser(baseURL: URL, credential: SeerrCredential) async throws -> SeerrUser {
        let url = baseURL.appendingPathComponent("/api/v1/auth/me")
        return try await perform(request: makeRequest(url: url, credential: credential))
    }

    /// Fetch the server's public settings (4K toggles, etc.).
    public func getPublicSettings(baseURL: URL) async throws -> SeerrPublicSettings {
        let url = baseURL.appendingPathComponent("/api/v1/settings/public")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request: request)
    }

    // MARK: - Discover Sliders

    public func getDiscoverSliders(baseURL: URL, credential: SeerrCredential) async throws -> [DiscoverSlider] {
        try await perform(request: makeRequest(
            url: baseURL.appendingPathComponent("/api/v1/settings/discover"),
            credential: credential
        ))
    }

    // MARK: - Private Helpers

    private func makeRequest(url: URL, apiKey: String) -> URLRequest {
        makeRequest(url: url, credential: .apiKey(apiKey))
    }

    private func makeRequest(url: URL, credential: SeerrCredential) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch credential {
        case let .apiKey(key):
            request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        case let .session(cookie):
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private func buildURL(base: URL, path: String, query: [String: String]) -> URL {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url ?? base
    }

    private func perform<T: Decodable>(request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.networkUnavailable }
        if let error = NetworkError.from(statusCode: http.statusCode) { throw error }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw NetworkError.decodingError(error.localizedDescription) }
    }

    // DEBUG — verbose variant used by testConnection. Logs raw body before decode and
    // throws a descriptive error if the HTTP status is not 200, instead of a generic
    // "parse error" when the body is e.g. an HTML login page or error JSON.
    private func performLogging<T: Decodable>(request: URLRequest, label: String) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("[SeerrDebug] \(label) — no HTTPURLResponse")
            throw NetworkError.networkUnavailable
        }
        if let raw = String(data: data, encoding: .utf8) {
            print("[SeerrDebug] \(label) HTTP \(http.statusCode) raw response: \(raw)")
        } else {
            print("[SeerrDebug] \(label) HTTP \(http.statusCode) (non-utf8, \(data.count) bytes)")
        }
        guard http.statusCode == 200 else {
            if let mapped = NetworkError.from(statusCode: http.statusCode) { throw mapped }
            throw NetworkError.serverError(http.statusCode)
        }
        do { return try decoder.decode(T.self, from: data) }
        catch {
            print("[SeerrDebug] \(label) decode failed: \(error)")
            throw NetworkError.decodingError("\(label): \(error.localizedDescription)")
        }
    }

    private func rawPerform(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.networkUnavailable }
        if let error = NetworkError.from(statusCode: http.statusCode) { throw error }
        return data
    }
}

// MARK: - SeerrCredential

/// Encapsulates how a request authenticates against Seerr.
/// Resolved by AppState for the current user before any API call.
public enum SeerrCredential: Sendable {
    case apiKey(String) // X-Api-Key header — shared across all tvOS profiles
    case session(String) // Cookie header — per tvOS profile
}
