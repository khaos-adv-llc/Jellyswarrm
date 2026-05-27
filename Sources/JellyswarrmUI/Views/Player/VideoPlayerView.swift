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

    public init(item: MediaItem) {
        self.item = item
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
            }
        }
        .onDisappear {
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

    struct SystemPlayerView: NSViewControllerRepresentable {
        let player: AVPlayer
        let onDismiss: () -> Void

        func makeNSViewController(context _: Context) -> AVPlayerViewController {
            let vc = AVPlayerViewController()
            vc.player = player
            vc.allowsPictureInPicturePlayback = true
            return vc
        }

        func updateNSViewController(_ vc: AVPlayerViewController, context _: Context) {
            vc.player = player
        }
    }
#else
    import UIKit

    struct SystemPlayerView: UIViewControllerRepresentable {
        let player: AVPlayer
        let onDismiss: () -> Void

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let vc = AVPlayerViewController()
            vc.player = player
            vc.allowsPictureInPicturePlayback = true
            vc.showsPlaybackControls = true
            // Coordinator handles the Done button dismiss
            vc.delegate = context.coordinator
            return vc
        }

        func updateUIViewController(_ vc: AVPlayerViewController, context _: Context) {
            vc.player = player
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(onDismiss: onDismiss)
        }

        final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
            let onDismiss: () -> Void
            init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

            #if os(tvOS)
                func playerViewControllerWillBeginDismissalTransition(_ playerViewController: AVPlayerViewController) {
                    onDismiss()
                }
            #endif
        }
    }
#endif
