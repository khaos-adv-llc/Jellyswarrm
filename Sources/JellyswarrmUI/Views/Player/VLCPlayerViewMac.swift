// MARK: - VLCPlayerViewMac.swift

// Jellyswarrm — LGPL-2.1-or-later

#if canImport(VLCKit) && os(macOS)
import AppKit
import SwiftUI
import VLCKit

struct VLCPlayerViewMac: NSViewRepresentable {
    let url: URL
    let startPosition: Float
    var onStopped: (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        context.coordinator.setup(in: view, url: url, startPosition: startPosition)
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onStopped: onStopped) }

    @MainActor
    final class Coordinator: NSObject, VLCMediaPlayerDelegate {
        let player = VLCMediaPlayer()
        var onStopped: (() -> Void)?

        init(onStopped: (() -> Void)?) { self.onStopped = onStopped }

        func setup(in view: NSView, url: URL, startPosition: Float) {
            player.drawable = view
            player.media = VLCMedia(url: url)
            player.delegate = self
            if startPosition > 0 { player.position = startPosition }
            player.play()
        }

        nonisolated func mediaPlayerStateChanged(_: Notification) {
            Task { @MainActor in
                if self.player.state == .stopped || self.player.state == .ended {
                    self.onStopped?()
                }
            }
        }

        deinit { player.stop() }
    }
}
#endif
