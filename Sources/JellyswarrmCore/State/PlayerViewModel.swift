// MARK: - PlayerViewModel.swift

// Jellyswarrm — GPL v3 with App Store exception

import AVFoundation
import Foundation
import JellyfinAPI
import Observation

@Observable
@MainActor
public final class PlayerViewModel {
    public var currentItem: MediaItem?
    public var playbackInfo: PlaybackInfo?
    public var selectedSource: MediaSource?
    public var playSessionId: String?
    public var playbackURL: URL?
    /// True when `playbackURL` points to a Jellyfin HLS transcode (main.m3u8).
    /// The HLS resource loader must be attached only in this case to bypass
    /// Jellyfin's HTTP 405 on HEAD requests for segment URLs.
    public var isHLSTranscode: Bool = false
    public var positionTicks: Int64 = 0
    public var durationTicks: Int64 = 0
    public var isPlaying: Bool = false
    public var isPaused: Bool = false
    public var isLoading: Bool = false
    public var error: NetworkError?

    // Playback options
    public var audioStreamIndex: Int?
    public var subtitleStreamIndex: Int?

    // Task-based mutex for loadPlayback. A Bool guard is not race-free here:
    // SwiftUI can call .task twice in quick succession and both invocations
    // can pass an `await`-suspended guard before either sets the flag. Using
    // a Task handle guarantees the second caller cancels the first and runs
    // alone — see loadPlayback.
    private var loadTask: Task<Void, Never>?

    /// Set to true once the player has actually rendered a frame (iOS:
    /// AVPlayerViewController.isReadyForDisplay → true; other platforms: after
    /// seek+play). Stop reports are skipped when this is false, so transient
    /// view lifecycle events during the SwiftUI → UIKit presentation do not
    /// zero out the server's stored resume position.
    public var hasStartedPlayback: Bool = false

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
    private let sdk = JellyfinSDKClient.shared

    public init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Load Playback

    public func loadPlayback(for item: MediaItem, startFromBeginning: Bool = false) async {
        // SwiftUI may re-run .task and call loadPlayback twice concurrently.
        // Cancel any prior in-flight load and replace it with a single new
        // task — both racing callers then await the same Task and the prior
        // PlaybackInfo + transcode session work is dropped before the second
        // request hits the network.
        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadPlayback(for: item, startFromBeginning: startFromBeginning)
        }
        loadTask = task
        await task.value
    }

    private func performLoadPlayback(for item: MediaItem, startFromBeginning: Bool) async {
        if Task.isCancelled { return }

        // Tear down any existing session before starting a new one. Without
        // this, a previous session's HLSProxyServer listener can stay bound
        // (port != 0) and the new session would inherit a stale port.
        if hasStartedPlayback || isHLSTranscode || playbackURL != nil {
            await stop()
        }
        if Task.isCancelled { return }

        guard let server = appState.currentServer,
              let token = appState.tokenForCurrentServer() else { return }

        isLoading = true
        error = nil
        currentItem = item

        do {
            // First call: get available media sources
            let info = try await api.getPlaybackInfo(server: server, token: token, itemId: item.id)
            if Task.isCancelled { return }
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
            if Task.isCancelled { return }

            let resolvedSource = resolvedInfo.mediaSources.first(where: { $0.id == source.id })
                ?? resolvedInfo.mediaSources.first
                ?? source
            selectedSource = resolvedSource
            playSessionId = resolvedInfo.playSessionId ?? info.playSessionId
            print("[Player] PlaySessionId: \(playSessionId ?? "-")")

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

            durationTicks = source.runTimeTicks ?? item.runtimeTicks ?? 0

            // Resolve resume position. Resume works via a local AVPlayer
            // seek AFTER the player is ready for display — we do NOT pass
            // StartTimeTicks to Jellyfin's HLS endpoint. Jellyfin would
            // happily generate a playlist whose first segment starts at the
            // resume timestamp, but the resulting segment has a PTS
            // discontinuity (no keyframe at PTS 0) and AVFoundation rejects
            // it with the "Playback Prohibited" icon. Letting Jellyfin
            // transcode from PTS 0 and seeking client-side avoids this.
            if startFromBeginning {
                positionTicks = 0
                print("[Resume] Caller requested start from beginning")
            } else {
                // Priority 1: local UserDefaults backup. Updated every 10s by
                // the player's periodic time observer, so it's always at least
                // as fresh as the server (which only updates on Stop reports
                // — and a Stop from a just-dismissed session races with this
                // new load).
                let key = "resume_\(item.id)"
                let localRaw = UserDefaults.standard.double(forKey: key)
                print("[Resume] Reading key: \(key), raw value: \(localRaw)")
                let localTicks = Int64(localRaw)

                if localTicks > 0 {
                    positionTicks = localTicks
                    print("[Resume] Local position: \(localTicks) ticks for \(item.id)")
                } else {
                    // Priority 2: server UserData (cross-device fallback).
                    do {
                        let serverTicks = try await sdk.resumeTicks(
                            server: server, token: token, itemId: item.id
                        )
                        if serverTicks > 0 {
                            positionTicks = serverTicks
                            print("[Resume] Server UserData position (SDK): \(positionTicks) ticks for \(item.id)")
                        } else {
                            print("[Resume] No saved position — starting from beginning")
                        }
                    } catch {
                        print("[Resume] SDK resumeTicks failed: \(error.localizedDescription) — starting from beginning")
                    }
                }
                print("[Resume] Starting from: \(positionTicks) ticks")
            }

            if !audioIsCompatible {
                // Incompatible audio (Opus, EAC3, TrueHD, DTS, FLAC) — transcode
                // through Jellyfin's HLS endpoint using MPEG-TS segments with
                // H.264 video + AAC audio. AVAudioSession is configured at app
                // launch so -12860 will not recur.
                let hlsURL = buildHLSTranscodeURL(
                    itemId: item.id,
                    source: resolvedSource,
                    audioStreamIndex: audioStream?.index ?? chosenAudio ?? 1,
                    server: server,
                    token: token
                )
                // Route through local proxy to convert HEAD→GET (Jellyfin returns 405 on HEAD).
                // Must await start() to avoid race where proxyURL() is called before
                // the listener has bound to a port (port=0 → AVPlayer fails instantly).
                if let hlsURL {
                    _ = try? await HLSProxyServer.shared.start()
                    print("[HLSProxy] Ready on port \(await HLSProxyServer.shared.port), building proxy URL")
                    playbackURL = await HLSProxyServer.shared.proxyURL(for: hlsURL) ?? hlsURL
                } else {
                    playbackURL = nil
                }
                isHLSTranscode = true
                print("[Player] HLS proxy URL: \(playbackURL?.absoluteString ?? "-")")
            } else if let directPath = resolvedSource.directStreamUrl {
                // Server provided a direct stream path
                playbackURL = resolvePlaybackURL(path: directPath, server: server, token: token)
                isHLSTranscode = false
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
                isHLSTranscode = false
                print("[Player] Using manually constructed direct stream URL: \(playbackURL?.absoluteString ?? "-")")
            } else {
                print("[Player] ERROR: no playback path available")
                throw NetworkError.emptyResponse
            }

            // NOTE: reportPlaybackStart is intentionally deferred until the
            // player actually renders a frame. See notifyPlaybackStarted().
            // Sending Start before the player begins playing means a spurious
            // stop (e.g. SwiftUI .onDisappear during the player presentation)
            // would race ahead of it and zero out the server's resume position.

        } catch let e as NetworkError {
            error = e
        } catch {
            self.error = .custom(error.localizedDescription)
        }

        isLoading = false
    }

    /// Called by the view layer once the player has rendered its first frame
    /// (iOS: AVPlayerViewController.isReadyForDisplay → true; other platforms:
    /// after seek+play returns). Sends the deferred Start report and arms the
    /// periodic progress reporter.
    public func notifyPlaybackStarted() async {
        guard !hasStartedPlayback else { return }
        hasStartedPlayback = true

        guard let item = currentItem,
              let source = selectedSource,
              let server = appState.currentServer,
              let token = appState.tokenForCurrentServer() else { return }

        // MIGRATED TO SDK. PlayMethod is now a typed enum, and we send
        // `.transcode` whenever we are using Jellyfin's HLS transcode endpoint
        // (previously the hand-rolled code mis-reported `DirectPlay` /
        // `DirectStream` for transcoded streams, which broke server-side
        // resume tracking).
        let method: PlayMethod = isHLSTranscode ? .transcode : .directStream
        try? await sdk.reportPlaybackStart(
            server: server,
            token: token,
            itemId: item.id,
            positionTicks: positionTicks,
            mediaSourceId: source.id,
            playSessionId: playSessionId,
            playMethod: method,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex
        )
        startProgressReporting()
    }

    // MARK: - Progress Reporting

    private func startProgressReporting() {
        reportingTask?.cancel()
        // Capture the session id at arming time. If the VM is reused or the
        // session changes, the closure exits without reporting. Combined with
        // [weak self], this double-guards against stale progress reports from
        // a teardown-survived task: when the VM has no other strong refs,
        // `self?` becomes nil and the loop exits, letting the VM deallocate.
        let capturedSessionId = playSessionId
        let interval = reportingInterval
        reportingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { break }
                guard self.playSessionId == capturedSessionId else { break }
                await self.reportProgress()
            }
        }
    }

    public func reportProgress() async {
        // MIGRATED TO SDK.
        guard let item = currentItem,
              let source = selectedSource,
              let server = appState.currentServer,
              let token = appState.tokenForCurrentServer() else { return }
        let method: PlayMethod = isHLSTranscode ? .transcode : .directStream
        try? await sdk.reportPlaybackProgress(
            server: server,
            token: token,
            itemId: item.id,
            positionTicks: positionTicks,
            isPaused: isPaused,
            mediaSourceId: source.id,
            playSessionId: playSessionId,
            playMethod: method
        )
        print("[Progress] Reported \(positionTicks) ticks to server")
    }

    public func stop() async {
        // If the player never actually rendered a frame, this is a spurious
        // teardown (e.g. SwiftUI's .onDisappear firing during the UIKit
        // player presentation). Skip the Stopped report and DO NOT reset
        // session state — the player is still loading and a state reset
        // would either tear down the in-flight session or let a re-run of
        // .task spawn a duplicate PlaybackInfo / transcode session.
        guard hasStartedPlayback else {
            // Still cancel the reporting task — if one somehow got armed
            // (defensive; shouldn't happen since notifyPlaybackStarted() arms
            // it), we don't want it leaking past view teardown.
            reportingTask?.cancel()
            reportingTask = nil
            print("[Progress] Skipping stop report — playback never started")
            return
        }

        reportingTask?.cancel()
        reportingTask = nil
        stopChapterObserver()

        if let item = currentItem,
           let source = selectedSource,
           let server = appState.currentServer,
           let token = appState.tokenForCurrentServer() {
            // MIGRATED TO SDK. Stop info doesn't carry PlayMethod in the SDK
            // type — Jellyfin already knows it from the matching Start report.
            try? await sdk.reportPlaybackStopped(
                server: server,
                token: token,
                itemId: item.id,
                positionTicks: positionTicks,
                mediaSourceId: source.id,
                playSessionId: playSessionId
            )
            print("[Progress] Stopped at \(positionTicks) ticks")
        }

        // Tear down the loopback HLS proxy. Leaving the previous NWListener
        // bound between sessions produces "Broken pipe" / "Connection reset
        // by peer" on the next playback attempt as AVPlayer hits stale
        // connections on the old port.
        if isHLSTranscode {
            await HLSProxyServer.shared.stop()
        }

        isPlaying = false
        hasStartedPlayback = false
        currentItem = nil
        playbackURL = nil
        isHLSTranscode = false
        isLoading = false
        loadTask = nil
        playSessionId = nil
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
