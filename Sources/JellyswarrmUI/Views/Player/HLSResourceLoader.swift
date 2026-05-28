// MARK: - HLSResourceLoader.swift

// Jellyswarrm — GPL v3 with App Store exception

import AVFoundation
import Foundation

/// Intercepts AVPlayer's HLS requests and proxies them as GET-only to Jellyfin.
/// Works around Jellyfin's HTTP 405 response to HEAD requests on segment URLs,
/// which crashes AVPlayer's HLS engine with -12860 (FigPlayer_MediaServiceDied).
final class HLSResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {

    static let customScheme = "jellyswarrm"
    static let realScheme = "https"

    /// Convert a real https:// URL to our custom scheme for AVURLAsset.
    static func customSchemeURL(from realURL: URL) -> URL? {
        guard var components = URLComponents(url: realURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = customScheme
        return components.url
    }

    /// Convert back from custom scheme to real https:// for fetching.
    private static func realURL(from customURL: URL) -> URL? {
        guard var components = URLComponents(url: customURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = realScheme
        return components.url
    }

    private var activeTasks: [AVAssetResourceLoadingRequest: URLSessionDataTask] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let customURL = loadingRequest.request.url,
              let realURL = Self.realURL(from: customURL) else {
            return false
        }

        var urlRequest = URLRequest(url: realURL)
        urlRequest.httpMethod = "GET"

        if let rangeHeader = loadingRequest.request.value(forHTTPHeaderField: "Range") {
            urlRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }

        print("[HLSLoader] GET \(realURL.lastPathComponent) ← intercepted")

        let task = session.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self = self else { return }

            defer { self.activeTasks.removeValue(forKey: loadingRequest) }

            if loadingRequest.isCancelled { return }

            if let error = error {
                print("[HLSLoader] Error: \(error.localizedDescription)")
                loadingRequest.finishLoading(with: error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let data = data else {
                loadingRequest.finishLoading(with: URLError(.badServerResponse))
                return
            }

            print("[HLSLoader] \(httpResponse.statusCode) \(realURL.lastPathComponent) (\(data.count) bytes)")

            if let contentRequest = loadingRequest.contentInformationRequest {
                contentRequest.contentType = httpResponse.mimeType ?? "video/MP2T"
                contentRequest.contentLength = Int64(data.count)
                contentRequest.isByteRangeAccessSupported = false
            }

            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
        }

        activeTasks[loadingRequest] = task
        task.resume()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        activeTasks[loadingRequest]?.cancel()
        activeTasks.removeValue(forKey: loadingRequest)
    }
}
