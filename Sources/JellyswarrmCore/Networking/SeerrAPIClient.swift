// MARK: - SeerrAPIClient.swift

// Jellyswarrm — GPL v3 with App Store exception

import Foundation

/// Thread-safe Jellyseerr/Overseerr API client.
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
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Authentication

    /// Test server reachability — no auth required.
    public func testConnection(baseURL: URL, apiKey: String) async throws -> SeerrStatus {
        let url = baseURL.appendingPathComponent("/api/v1/status")
        let request = makeRequest(url: url, apiKey: apiKey)
        return try await perform(request: request)
    }

    /// Authenticate using Jellyfin username + password.
    /// Returns the raw Set-Cookie string to store in the per-user Keychain.
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

        // Extract session cookie from response headers
        let headers = http.allHeaderFields as? [String: String] ?? [:]
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        guard let sessionCookie = cookies.first(where: { $0.name == "connect.sid" || $0.name.hasPrefix("session") })?
            .value
            ?? cookies.first?.value,
            !sessionCookie.isEmpty
        else {
            throw NetworkError.custom("Jellyseerr did not return a session cookie. Check your credentials.")
        }
        // Return the full Set-Cookie header value so we can replay it exactly
        return headers["Set-Cookie"] ?? "\(cookies.first?.name ?? "session")=\(sessionCookie)"
    }

    /// Authenticate using a local Seerr account (email + password).
    /// Returns the raw Set-Cookie string to store in the per-user Keychain.
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

        let headers = http.allHeaderFields as? [String: String] ?? [:]
        let rawCookie = headers["Set-Cookie"] ?? ""
        if rawCookie.isEmpty {
            throw NetworkError.custom("Jellyseerr did not return a session cookie. Check your credentials.")
        }
        return rawCookie
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
