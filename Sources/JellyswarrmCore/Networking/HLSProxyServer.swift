// MARK: - HLSProxyServer.swift

// Jellyswarrm — GPL v3 with App Store exception

import Foundation
import Network

/// Minimal HTTP/1.1 loopback proxy that converts HEAD→GET for Jellyfin HLS endpoints.
/// AVPlayer connects to http://127.0.0.1:<port>/ with its native HLS engine intact.
///
/// Why: Jellyfin returns HTTP 405 for HEAD on `/Videos/{id}/main.m3u8` and
/// `/Videos/{id}/hls1/main/*.ts`. AVPlayer's HLS engine preflights segments with
/// HEAD, which crashes the video decoder (-12860). A custom `AVAssetResourceLoader`
/// scheme disables AVPlayer's native HLS engine entirely, so we run a real
/// loopback HTTP server instead.
public actor HLSProxyServer {
    public static let shared = HLSProxyServer()

    private var listener: NWListener?
    public private(set) var port: UInt16 = 0
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    /// Start the proxy. Safe to call multiple times — only starts once.
    public func start() async throws {
        guard listener == nil else { return }

        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handle(connection: connection) }
        }

        listener.start(queue: .global(qos: .userInitiated))

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    cont.resume()
                case .failed(let error):
                    cont.resume(throwing: error)
                default:
                    break
                }
            }
        }

        if case .port(let assignedPort) = listener.port {
            self.port = assignedPort.rawValue
            print("[HLSProxy] Listening on 127.0.0.1:\(self.port)")
        }
    }

    /// Rewrite a Jellyfin HLS URL to go through the proxy.
    public func proxyURL(for originalURL: URL) -> URL? {
        guard var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false) else { return nil }
        let originalScheme = originalURL.scheme ?? "https"
        let originalHost = originalURL.host ?? ""
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "_proxy_host", value: originalHost))
        queryItems.append(URLQueryItem(name: "_proxy_scheme", value: originalScheme))
        components.queryItems = queryItems
        return components.url
    }

    private func handle(connection: NWConnection) async {
        connection.start(queue: .global(qos: .userInitiated))

        guard let requestData = await receive(from: connection),
              let requestString = String(data: requestData, encoding: .utf8) else {
            connection.cancel()
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { connection.cancel(); return }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { connection.cancel(); return }

        var method = parts[0]
        let path = parts[1]

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let headerParts = line.components(separatedBy: ": ")
            if headerParts.count >= 2 {
                headers[headerParts[0].lowercased()] = headerParts.dropFirst().joined(separator: ": ")
            }
        }

        guard var urlComponents = URLComponents(string: "http://placeholder" + path) else {
            connection.cancel(); return
        }

        let queryItems = urlComponents.queryItems ?? []
        let proxyHost = queryItems.first(where: { $0.name == "_proxy_host" })?.value ?? ""
        let proxyScheme = queryItems.first(where: { $0.name == "_proxy_scheme" })?.value ?? "https"

        urlComponents.queryItems = queryItems.filter { $0.name != "_proxy_host" && $0.name != "_proxy_scheme" }
        urlComponents.scheme = proxyScheme
        urlComponents.host = proxyHost
        urlComponents.port = nil

        guard let targetURL = urlComponents.url else {
            connection.cancel(); return
        }

        let originalMethod = method
        if method == "HEAD" { method = "GET" }

        print("[HLSProxy] \(originalMethod)→\(method) \(targetURL.lastPathComponent)")

        var request = URLRequest(url: targetURL)
        request.httpMethod = method
        if let range = headers["range"] { request.setValue(range, forHTTPHeaderField: "Range") }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { connection.cancel(); return }

            let responseBody = originalMethod == "HEAD" ? Data() : data

            var responseHeaders = "HTTP/1.1 \(httpResponse.statusCode) OK\r\n"
            responseHeaders += "Content-Type: \(httpResponse.mimeType ?? "application/octet-stream")\r\n"
            responseHeaders += "Content-Length: \(responseBody.count)\r\n"
            responseHeaders += "Connection: close\r\n"
            responseHeaders += "\r\n"

            var responseData = responseHeaders.data(using: .utf8)!
            responseData.append(responseBody)

            await send(data: responseData, to: connection)
        } catch {
            let errResponse = "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            await send(data: errResponse.data(using: .utf8)!, to: connection)
        }

        connection.cancel()
    }

    private func receive(from connection: NWConnection) async -> Data? {
        return await withCheckedContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                cont.resume(returning: data)
            }
        }
    }

    private func send(data: Data, to connection: NWConnection) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in cont.resume() })
        }
    }
}
