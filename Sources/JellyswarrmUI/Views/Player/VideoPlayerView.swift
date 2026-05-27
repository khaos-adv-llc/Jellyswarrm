// MARK: - VideoPlayerView.swift

// Jellyswarrm — GPL v3 with App Store exception

import AVKit
import JellyswarrmCore
import SwiftUI

public struct VideoPlayerView: View {
    let item: MediaItem
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var playerVM: PlayerViewModel
    @State private var player: AVPlayer?
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    public init(item: MediaItem) {
        self.item = item
        _playerVM = State(initialValue: PlayerViewModel(appState: AppState()))
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                #if os(tvOS)
                    // On tvOS use the full AVPlayerViewController via representable
                    TVOSPlayerView(player: player, item: item, playerVM: playerVM)
                        .ignoresSafeArea()
                #else
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                        .onTapGesture { toggleControls() }

                    if showControls {
                        customControls
                            .transition(.opacity)
                    }
                #endif
            } else if playerVM.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else if let error = playerVM.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text("Playback Error")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(error.errorDescription ?? "Unknown error")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .task {
            playerVM = PlayerViewModel(appState: appState)
            await playerVM.loadPlayback(for: item)
            if let url = playerVM.playbackURL {
                player = AVPlayer(url: url)
                // Seek to last position
                if playerVM.positionTicks > 0 {
                    let seconds = playerVM.positionTicks.ticksToSeconds
                    await player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
                }
                player?.play()
                playerVM.isPlaying = true
                scheduleHideControls()
            }
        }
        .onDisappear {
            Task { await playerVM.stop() }
            player?.pause()
            player = nil
        }
    }

    // MARK: - Custom Controls (non-tvOS)

    #if !os(tvOS)
        private var customControls: some View {
            VStack {
                // Top bar
                HStack {
                    Button {
                        Task { await playerVM.stop() }
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(item.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    Menu {
                        if !playerVM.audioStreams.isEmpty {
                            Menu("Audio Track") {
                                ForEach(playerVM.audioStreams) { stream in
                                    Button(stream.displayTitle ?? "Track \(stream.index)") {
                                        playerVM.audioStreamIndex = stream.index
                                    }
                                }
                            }
                        }
                        if !playerVM.subtitleStreams.isEmpty {
                            Menu("Subtitles") {
                                Button("Off") { playerVM.subtitleStreamIndex = nil }
                                ForEach(playerVM.subtitleStreams) { stream in
                                    Button(stream.displayTitle ?? stream.language ?? "Track \(stream.index)") {
                                        playerVM.subtitleStreamIndex = stream.index
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .padding()
                .background(LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .top, endPoint: .bottom
                ))

                Spacer()

                // Bottom controls
                VStack(spacing: 12) {
                    // Seek bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity(0.3))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white)
                                .frame(width: geo.size.width * playerVM.progressFraction, height: 4)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let fraction = max(0, min(1, value.location.x / geo.size.width))
                                    let newTicks = Int64(fraction * Double(playerVM.durationTicks))
                                    playerVM.positionTicks = newTicks
                                    let seconds = newTicks.ticksToSeconds
                                    player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
                                }
                        )
                    }
                    .frame(height: 4)

                    HStack {
                        Text(playerVM.currentTimeString)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(playerVM.durationString)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    // Play/pause + skip
                    HStack(spacing: 32) {
                        Button {
                            skipBackward()
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.title)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button {
                            togglePlayPause()
                        } label: {
                            Image(systemName: playerVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button {
                            skipForward()
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.title)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            .animation(.easeInOut(duration: 0.2), value: showControls)
        }

        private func togglePlayPause() {
            if playerVM.isPlaying {
                player?.pause()
                playerVM.isPlaying = false
                playerVM.isPaused = true
            } else {
                player?.play()
                playerVM.isPlaying = true
                playerVM.isPaused = false
                scheduleHideControls()
            }
        }

        private func skipForward() {
            let seconds = playerVM.positionTicks.ticksToSeconds + 30
            let ticks = seconds.secondsToTicks
            playerVM.positionTicks = ticks
            player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }

        private func skipBackward() {
            let seconds = max(0, playerVM.positionTicks.ticksToSeconds - 15)
            let ticks = seconds.secondsToTicks
            playerVM.positionTicks = ticks
            player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }

        private func toggleControls() {
            withAnimation {
                showControls.toggle()
            }
            if showControls { scheduleHideControls() }
        }

        private func scheduleHideControls() {
            hideControlsTask?.cancel()
            hideControlsTask = Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation { showControls = false }
            }
        }
    #endif
}

// MARK: - tvOS AVPlayerViewController

#if os(tvOS)
    import UIKit

    struct TVOSPlayerView: UIViewControllerRepresentable {
        let player: AVPlayer
        let item: MediaItem
        let playerVM: PlayerViewModel

        func makeUIViewController(context _: Context) -> AVPlayerViewController {
            let vc = AVPlayerViewController()
            vc.player = player
            vc.allowsPictureInPicturePlayback = true
            return vc
        }

        func updateUIViewController(_ vc: AVPlayerViewController, context _: Context) {
            vc.player = player
        }
    }
#endif
