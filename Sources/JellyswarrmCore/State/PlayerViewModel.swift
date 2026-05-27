// MARK: - PlayerViewModel.swift
// Jellyswarrm — GPL v3 with App Store exception

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

    // Progress reporting
    private var reportingTask: Task<Void, Never>?
    private let reportingInterval: TimeInterval = 10  // seconds

    private let appState: AppState
    private let api = JellyfinAPIClient.shared

    public init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Load Playback

    public func loadPlayback(for item: MediaItem) async {
        guard let server = appState.currentServer,
              let token = appState.tokenForCurrentServer() else { return }

        isLoading = true
        error = nil
        currentItem = item

        do {
            let info = try await api.getPlaybackInfo(server: server, token: token, itemId: item.id)
            playbackInfo = info

            guard let source = info.mediaSources.first else {
                throw NetworkError.emptyResponse
            }
            selectedSource = source

            // Set default audio/subtitle streams
            audioStreamIndex = source.defaultAudioStreamIndex
            subtitleStreamIndex = source.defaultSubtitleStreamIndex

            // Prefer direct play, fall back to transcode
            if source.supportsDirectPlay, let directURL = source.directStreamUrl {
                playbackURL = server.baseURL.appendingPathComponent(directURL)
            } else if let transURL = source.transcodingUrl {
                playbackURL = server.baseURL.appendingPathComponent(transURL)
            }

            durationTicks = source.runTimeTicks ?? item.runtimeTicks ?? 0

            // Resume from last position
            if let userData = item.userData, userData.hasProgress {
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
}
