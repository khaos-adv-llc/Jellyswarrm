// MARK: - VLCPlayerView.swift

// Jellyswarrm — LGPL-2.1-or-later

#if canImport(MobileVLCKit) && !os(macOS)
import MobileVLCKit
import SwiftUI
import UIKit

struct VLCPlayerView: UIViewRepresentable {
    let url: URL
    let startPosition: Float
    var onStopped: (() -> Void)?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.setup(in: view, url: url, startPosition: startPosition)
        return view
    }

    func updateUIView(_: UIView, context _: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onStopped: onStopped) }

    @MainActor
    final class Coordinator: NSObject, VLCMediaPlayerDelegate {
        let player = VLCMediaPlayer()
        var onStopped: (() -> Void)?

        init(onStopped: (() -> Void)?) {
            self.onStopped = onStopped
        }

        func setup(in view: UIView, url: URL, startPosition: Float) {
            player.drawable = view
            let media = VLCMedia(url: url)
            media.addOptions(["no-video-title-show": true])
            player.media = media
            player.delegate = self
            if startPosition > 0 {
                player.position = startPosition
            }
            player.play()
        }

        nonisolated func mediaPlayerStateChanged(_: Notification) {
            Task { @MainActor in
                if self.player.state == .stopped || self.player.state == .ended {
                    self.onStopped?()
                }
            }
        }

        deinit {
            player.stop()
        }
    }
}
#endif
