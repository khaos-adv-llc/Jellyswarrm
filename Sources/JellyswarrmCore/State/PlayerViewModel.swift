// MARK: - PlayerViewModel.swift

// Jellyswarrm — GPL v3 with App Store exception

import AVFoundation
import Foundation
import Observation

@Observable
@MainActor
public final class PlayerViewModel {
    public var currentItem: MediaItem?
    public var playbackInfo: PlaybackInfo?
    public var selectedSource: MediaSource?
    public var playbackURL: URL?
    public var positionTicks: Int64 = 0
    public var durationTicks: Int64 = 0
    public var isPlaying: Bool = false
    public var isPaused: Bool = false
    public var isLoading: Bool = false
    public var error: NetworkError?

    // Playback options
    public var audioStreamIndex: Int?
    public var subtitleStreamIndex: Int?

    // Synchronous mutex for loadPlayback. `@Observable` properties have async
    // observation semantics — two concurrent callers can both see isLoading
    // == false before either sets it true. A plain stored Bool gives us
    // atomic test-and-set on the main actor.
    private var _loadingStarted: Bool = false

    // Current chapter name (updated by periodic time observer)
    public var currentChapterName: String?

    // Progress reporting
    private var reportingTask: Task<Void, Never>?
    private let reportingInterval: TimeInterval = 10 // seconds

    // Chapter observer
    private var chapterObserverToken: Any?
    private weak var chapterObserverPlayer: AVPlayer?

    private let appState: AppState
    private let api = JellyfinAPIClient.shared

    public init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Load Playback

    public func loadPlayback(for item: MediaItem, startFromBeginning: Bool = false) async {
        // Idempotency guard: SwiftUI may re-run .task and call loadPlayback
        // twice concurrently. Two PlaybackInfo POSTs + two transcode sessions
        // confuses Jellyfin and contributes to AVPlayer hitting an empty
        // segment 0 (FigPlayer_MediaServiceDied / -12860).
        guard !_loadingStarted else { return }
        _loadingStarted = true
        defer { if playbackURL == nil { _loadingStarted = false } }

        guard let server = appState.currentServer,
              let token = appState.tokenForCurrentServer() else { return }

        isLoading = true
        error = nil
        currentItem = item

        do {
            // First call: get available media sources
            let info = try await api.getPlaybackInfo(server: server, token: token, itemId: item.id)
            playbackInfo = info

            guard let source = info.mediaSources.first else {
                throw NetworkError.emptyResponse
            }

            let chosenAudio = source.defaultAudioStreamIndex
            let chosenSub = source.defaultSubtitleStreamIndex
            audioStreamIndex = chosenAudio
            subtitleStreamIndex = chosenSub

            // Second call with mediaSourceId — Jellyfin only populates
            // directStreamUrl / transcodingUrl when a specific source is requested
            let resolvedInfo = try await api.getPlaybackInfo(
                server: server,
                token: token,
                itemId: item.id,
                mediaSourceId: source.id,
                audioStreamIndex: chosenAudio,
                subtitleStreamIndex: chosenSub
            )

            let resolvedSource = resolvedInfo.mediaSources.first(where: { $0.id == source.id })
                ?? resolvedInfo.mediaSources.first
                ?? source
            selectedSource = resolvedSource

            print("[Player] source: \(resolvedSource.id) container=\(resolvedSource.container ?? "-")")
            print("[Player] directStreamUrl: \(resolvedSource.directStreamUrl ?? "-")")
            print("[Player] transcodingUrl: \(resolvedSource.transcodingUrl ?? "-")")

            // Pick the audio stream we'll actually play and check if AVPlayer can
            // direct-stream it. EAC3 / Opus / TrueHD / DTS / FLAC fail when remuxed
            // into MP4 over HTTP — we must transcode just the audio in that case.
            let audioStreams = resolvedSource.mediaStreams?.filter { $0.type == .audio } ?? []
            let audioStream = audioStreams.first(where: { $0.index == chosenAudio })
                ?? audioStreams.first(where: { $0.isDefault })
                ?? audioStreams.first
            let audioCodec = audioStream?.codec?.lowercased() ?? ""
            let audioIsCompatible = AudioCompatibility.isDirectPlayable(audioCodec)

            if audioIsCompatible {
                print("[Player] Audio codec '\(audioCodec)' is direct-playable, using direct stream")
            } else {
                print("[Player] Audio codec '\(audioCodec)' — will HLS-transcode to H.264+AAC (TS)")
            }

            if !audioIsCompatible {
                // Incompatible audio (Opus, EAC3, TrueHD, DTS, FLAC) — transcode
                // through Jellyfin's HLS endpoint using MPEG-TS segments with
                // H.264 video + AAC audio. AVAudioSession is configured at app
                // launch so -12860 will not recur.
                playbackURL = buildHLSTranscodeURL(
                    itemId: item.id,
                    source: resolvedSource,
                    audioStreamIndex: audioStream?.index ?? chosenAudio ?? 1,
                    server: server,
                    token: token
                )
                print("[Player] Using HLS TS transcode URL: \(playbackURL?.absoluteString ?? "-")")
            } else if let directPath = resolvedSource.directStreamUrl {
                // Server provided a direct stream path
                playbackURL = resolvePlaybackURL(path: directPath, server: server, token: token)
                print("[Player] Using server-provided stream URL")
            } else if resolvedSource.supportsDirectStream {
                // Jellyfin didn't return a URL but says direct stream is supported.
                // Construct the VideoStream URL manually — this is the standard pattern.
                playbackURL = buildDirectStreamURL(
                    source: resolvedSource,
                    server: server,
                    token: token,
                    audioIndex: chosenAudio,
                    subtitleIndex: chosenSub
                )
                print("[Player] Using manually constructed direct stream URL: \(playbackURL?.absoluteString ?? "-")")
            } else {
                print("[Player] ERROR: no playback path available")
                throw NetworkError.emptyResponse
            }

            durationTicks = source.runTimeTicks ?? item.runtimeTicks ?? 0

            // Resume from last position unless caller asked to restart
            if startFromBeginning {
                positionTicks = 0
            } else if let userData = item.userData, userData.hasProgress {
                positionTicks = userData.playbackPositionTicks
            }

            // Report playback start
            try await api.reportPlaybackStart(
                server: server,
                token: token,
                itemId: item.id,
                positionTicks: positionTicks,
                mediaSourceId: source.id,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex
            )

            startProgressReporting()

        } catch let e as NetworkError {
            error = e
        } catch {
            self.error = .custom(error.localizedDescription)
        }

        isLoading = false
    }

    // MARK: - Progress Reporting

    private func startProgressReporting() {
        reportingTask?.cancel()
        reportingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(reportingInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await reportProgress()
            }
        }
    }

    public func reportProgress() async {
        guard let item = currentItem,
              let source = selectedSource,
              let server = appState.currentServer,
              let token = appState.tokenForCurrentServer() else { return }
        try? await api.reportPlaybackProgress(
            server: server,
            token: token,
            itemId: item.id,
            positionTicks: positionTicks,
            isPaused: isPaused,
            mediaSourceId: source.id
        )
    }

    public func stop() async {
        reportingTask?.cancel()
        stopChapterObserver()
        guard let item = currentItem,
              let source = selectedSource,
              let server = appState.currentServer,
              let token = appState.tokenForCurrentServer() else { return }
        try? await api.reportPlaybackStopped(
            server: server,
            token: token,
            itemId: item.id,
            positionTicks: positionTicks,
            mediaSourceId: source.id
        )
        isPlaying = false
        currentItem = nil
        playbackURL = nil
        isLoading = false
        _loadingStarted = false
    }

    // MARK: - Computed

    public var progressFraction: Double {
        guard durationTicks > 0 else { return 0 }
        return min(1.0, Double(positionTicks) / Double(durationTicks))
    }

    public var currentTimeString: String {
        positionTicks.ticksToPlaybackString
    }

    public var durationString: String {
        durationTicks.ticksToPlaybackString
    }

    public var audioStreams: [MediaStream] {
        selectedSource?.mediaStreams?.filter { $0.type == .audio } ?? []
    }

    public var subtitleStreams: [MediaStream] {
        selectedSource?.mediaStreams?.filter { $0.type == .subtitle } ?? []
    }

    // MARK: - Chapter Metadata

    /// Configures an `AVPlayerItem` for playback. Currently only removes any
    /// artificial peak-bitrate cap so HDR / Dolby Vision direct play uses full bitrate.
    public func configurePlayerItem(_ playerItem: AVPlayerItem) {
        playerItem.preferredPeakBitRate = 0
    }

    /// Returns the chapter name for the given playback position ticks, or nil if no chapters.
    public func currentChapterName(atTicks ticks: Int64, chapters: [ChapterInfo]) -> String? {
        chapters
            .filter { ($0.startPositionTicks ?? 0) <= ticks }
            .last?.name
    }

    /// Installs a 1-second periodic time observer that updates
    /// `currentChapterName` as playback progresses.
    public func startChapterObserver(on player: AVPlayer, chapters: [ChapterInfo]) {
        stopChapterObserver()
        guard !chapters.isEmpty else { return }
        chapterObserverPlayer = player
        chapterObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let ticks = Int64(time.seconds * 10_000_000)
            self?.currentChapterName = self?.currentChapterName(atTicks: ticks, chapters: chapters)
        }
    }

    public func stopChapterObserver() {
        if let token = chapterObserverToken {
            chapterObserverPlayer?.removeTimeObserver(token)
        }
        chapterObserverToken = nil
        chapterObserverPlayer = nil
        currentChapterName = nil
    }

    // MARK: - URL Helpers

    /// Constructs a Jellyfin direct-stream URL manually.
    /// Used when PlaybackInfo returns SupportsDirectStream=true but no DirectStreamUrl.
    /// Pattern: /Videos/{id}/stream.{container}?Static=true&MediaSourceId={id}&api_key={token}
    private func buildDirectStreamURL(
        source: MediaSource,
        server: JellyfinServer,
        token: String,
        audioIndex: Int?,
        subtitleIndex: Int?
    ) -> URL? {
        // Always request MP4 container — AVPlayer handles HEVC/DV/HDR10 inside MP4
        // natively on iPhone 12+ via VideoToolbox. MKV is not a streamable container.
        // Jellyfin remuxes on the fly with no re-encode (fast, low CPU).
        let container = "mp4"
        let base = server.baseURL.absoluteString.hasSuffix("/")
            ? server.baseURL.absoluteString
            : server.baseURL.absoluteString + "/"
        let path = "Videos/\(source.id)/stream.\(container)"
        guard var components = URLComponents(string: base + path) else { return nil }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "Static", value: "true"),
            URLQueryItem(name: "MediaSourceId", value: source.id),
            URLQueryItem(name: "DeviceId", value: UIDeviceHelper.deviceId),
            URLQueryItem(name: "api_key", value: token),
        ]
        if let tag = source.eTag { items.append(URLQueryItem(name: "Tag", value: tag)) }
        if let a = audioIndex { items.append(URLQueryItem(name: "AudioStreamIndex", value: "\(a)")) }
        if let s = subtitleIndex { items.append(URLQueryItem(name: "SubtitleStreamIndex", value: "\(s)")) }
        components.queryItems = items
        return components.url
    }

    /// Constructs a Jellyfin HLS transcode URL that produces H.264 + AAC
    /// inside MPEG-TS segments.
    ///
    /// We force `Container=ts` because Jellyfin's fMP4 HLS output is broken
    /// (missing `#EXT-X-MAP` init segment, wrong `#EXT-X-VERSION` header).
    /// `MaxVideoBitDepth=8` strips HDR which is required for H.264 output.
    private func buildHLSTranscodeURL(
        itemId: String,
        source: MediaSource,
        audioStreamIndex: Int,
        server: JellyfinServer,
        token: String
    ) -> URL? {
        let base = server.baseURL.absoluteString.hasSuffix("/")
            ? server.baseURL.absoluteString
            : server.baseURL.absoluteString + "/"
        let path = "Videos/\(itemId)/main.m3u8"
        guard var components = URLComponents(string: base + path) else { return nil }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "DeviceId", value: UIDeviceHelper.deviceId),
            URLQueryItem(name: "MediaSourceId", value: source.id),
            URLQueryItem(name: "VideoCodec", value: "h264"),
            URLQueryItem(name: "AudioCodec", value: "aac"),
            URLQueryItem(name: "AudioBitrate", value: "192000"),
            URLQueryItem(name: "VideoBitrate", value: "8000000"),
            URLQueryItem(name: "MaxVideoBitDepth", value: "8"),
            URLQueryItem(name: "Container", value: "ts"),
            URLQueryItem(name: "TranscodingMaxAudioChannels", value: "2"),
            URLQueryItem(name: "AudioStreamIndex", value: "\(audioStreamIndex)"),
        ]
        if let tag = source.eTag { items.append(URLQueryItem(name: "Tag", value: tag)) }
        items.append(URLQueryItem(name: "api_key", value: token))
        components.queryItems = items
        let url = components.url
        if let url = url {
            print("[Player] HLS transcode URL (main.m3u8 direct): \(url)")
        }
        return url
    }

    /// Resolves a Jellyfin path (e.g. "/Videos/id/stream.mp4?params")
    /// against the server base URL and appends the auth token so AVPlayer
    /// can fetch it without custom headers.
    private func resolvePlaybackURL(path: String, server: JellyfinServer, token: String) -> URL? {
        // If path is already an absolute URL string, use it directly
        if path.hasPrefix("http") {
            guard var components = URLComponents(string: path) else { return nil }
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "api_key" }) {
                items.append(URLQueryItem(name: "api_key", value: token))
            }
            components.queryItems = items
            return components.url
        }

        // Relative path — resolve against base URL
        let base = server.baseURL.absoluteString.hasSuffix("/")
            ? server.baseURL.absoluteString
            : server.baseURL.absoluteString + "/"
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let fullString = base + cleanPath

        guard var components = URLComponents(string: fullString) else { return nil }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "api_key" }) {
            items.append(URLQueryItem(name: "api_key", value: token))
        }
        components.queryItems = items
        return components.url
    }
}
