// MARK: - VideoPlayerView.swift

// Jellyswarrm — GPL v3 with App Store exception

import AVKit
import JellyswarrmCore
import SwiftUI

public struct VideoPlayerView: View {
    let item: MediaItem
    let startFromBeginning: Bool
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var playerVM: PlayerViewModel
    @State private var player: AVPlayer?

    public init(item: MediaItem, startFromBeginning: Bool = false) {
        self.item = item
        self.startFromBeginning = startFromBeginning
        _playerVM = State(initialValue: PlayerViewModel(appState: AppState()))
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                // Use AVPlayerViewController on all platforms:
                // - Correctly renders HDR / Dolby Vision colour
                // - Provides built-in transport controls + dismiss button
                // - Supports Picture-in-Picture and AirPlay out of the box
                SystemPlayerView(player: player, onDismiss: { dismiss() })
                    .ignoresSafeArea()

                #if os(iOS)
                if let chapterName = playerVM.currentChapterName {
                    VStack {
                        Spacer()
                        Text(chapterName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.4), in: Capsule())
                            .transition(.opacity)
                            .padding(.bottom, 120)
                    }
                    .allowsHitTesting(false)
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
            await playerVM.loadPlayback(for: item, startFromBeginning: startFromBeginning)
            if let url = playerVM.playbackURL {
                let playerItem = AVPlayerItem(url: url)
                // Don't artificially cap bitrate — let direct play use full bitrate
                // for HDR / Dolby Vision.
                playerItem.preferredPeakBitRate = 0
                playerVM.configurePlayerItem(playerItem)
                let avPlayer = AVPlayer(playerItem: playerItem)
                player = avPlayer
                // Seek to last position (skipped when restarting)
                if playerVM.positionTicks > 0 {
                    let seconds = playerVM.positionTicks.ticksToSeconds
                    await avPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
                }
                avPlayer.play()
                playerVM.isPlaying = true
                if let chapters = playerVM.currentItem?.chapters, !chapters.isEmpty {
                    playerVM.startChapterObserver(on: avPlayer, chapters: chapters)
                }
            }
        }
        .onDisappear {
            playerVM.stopChapterObserver()
            Task { await playerVM.stop() }
            player?.pause()
            player = nil
        }
    }
}

// MARK: - System AVPlayerViewController (iOS, iPadOS, tvOS, macOS)
// Using AVPlayerViewController on all platforms ensures:
// - Correct HDR / Dolby Vision tone-mapping via VideoToolbox
// - Native transport bar with working dismiss / done button
// - Picture-in-Picture and AirPlay support

#if os(macOS)
    import AppKit

    // macOS has no AVPlayerViewController — use AVPlayerView from AVKit (AppKit).
    struct SystemPlayerView: NSViewRepresentable {
        let player: AVPlayer
        let onDismiss: () -> Void

        func makeNSView(context _: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.player = player
            view.controlsStyle = .inline
            view.showsFullScreenToggleButton = true
            view.allowsPictureInPicturePlayback = true
            return view
        }

        func updateNSView(_ nsView: AVPlayerView, context _: Context) {
            if nsView.player !== player {
                nsView.player = player
            }
        }
    }
#else
    import UIKit

    struct SystemPlayerView: UIViewControllerRepresentable {
        let player: AVPlayer
        let onDismiss: () -> Void

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let playerVC = AVPlayerViewController()
            playerVC.player = player
            playerVC.showsPlaybackControls = true
            playerVC.videoGravity = .resizeAspect
            playerVC.allowsPictureInPicturePlayback = true
            #if os(iOS)
                playerVC.updatesNowPlayingInfoCenter = true
                playerVC.entersFullScreenWhenPlaybackBegins = false
            #endif
            playerVC.delegate = context.coordinator

            #if os(iOS)
                // Fallback for the UIKit idle-timer bug when AVPlayerViewController
                // is hosted by SwiftUI: a transparent single-tap recognizer toggles
                // showsPlaybackControls and schedules a manual auto-hide. UseHandled
                // so we don't swallow taps the system controls need (they sit above
                // the contentOverlayView).
                let tap = UITapGestureRecognizer(
                    target: context.coordinator,
                    action: #selector(Coordinator.handleTap)
                )
                tap.cancelsTouchesInView = false
                tap.delegate = context.coordinator
                playerVC.contentOverlayView?.addGestureRecognizer(tap)
                context.coordinator.playerVC = playerVC
            #endif

            return playerVC
        }

        func updateUIViewController(_ playerVC: AVPlayerViewController, context _: Context) {
            if playerVC.player !== player {
                playerVC.player = player
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(onDismiss: onDismiss)
        }

        final class Coordinator: NSObject, AVPlayerViewControllerDelegate, UIGestureRecognizerDelegate {
            let onDismiss: () -> Void
            weak var playerVC: AVPlayerViewController?
            private var hideTask: Task<Void, Never>?

            init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

            #if os(iOS)
                @objc func handleTap() {
                    guard let playerVC else { return }
                    let willShow = !playerVC.showsPlaybackControls
                    playerVC.showsPlaybackControls = willShow
                    hideTask?.cancel()
                    if willShow {
                        hideTask = Task { [weak self] in
                            try? await Task.sleep(for: .seconds(3))
                            guard !Task.isCancelled else { return }
                            await MainActor.run { self?.playerVC?.showsPlaybackControls = false }
                        }
                    }
                }

                func gestureRecognizer(
                    _: UIGestureRecognizer,
                    shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
                ) -> Bool {
                    true
                }
            #endif

            #if os(tvOS)
                func playerViewControllerWillBeginDismissalTransition(_ playerViewController: AVPlayerViewController) {
                    onDismiss()
                }
            #endif
        }
    }
#endif
