// Jellyswarrm — LGPL-2.1-or-later
//
// Platform-agnostic VLC engine abstraction. Concrete VLC calls are gated by
// `canImport` so JellyswarrmCore continues to build cleanly when the VLC
// pods (TVVLCKit / MobileVLCKit / VLCKit) have not yet been installed via
// `pod install`.

import Foundation

#if canImport(TVVLCKit)
import TVVLCKit
typealias VLCMediaPlayerAlias = VLCMediaPlayer
typealias VLCMediaAlias = VLCMedia
#elseif canImport(MobileVLCKit)
import MobileVLCKit
typealias VLCMediaPlayerAlias = VLCMediaPlayer
typealias VLCMediaAlias = VLCMedia
#elseif canImport(VLCKit)
import VLCKit
typealias VLCMediaPlayerAlias = VLCMediaPlayer
typealias VLCMediaAlias = VLCMedia
#endif

#if canImport(TVVLCKit) || canImport(MobileVLCKit) || canImport(VLCKit)
/// Wraps `VLCMediaPlayer` with a Swift-native interface.
///
/// Hardware decoding via VideoToolbox is requested up front; VLC falls back
/// to software decoding automatically on failure (e.g. DV Profile 7 with no
/// VT support on the device).
@MainActor
public final class VLCEngine: NSObject, ObservableObject {

    public enum State {
        case idle
        case loading
        case playing
        case paused
        case stopped
        case error(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var position: Float = 0
    @Published public private(set) var duration: Int32 = 0

    private let player: VLCMediaPlayerAlias

    public override init() {
        // VideoToolbox hardware decode; VLC falls back to software when
        // VT cannot handle the codec/profile combination.
        player = VLCMediaPlayerAlias(options: ["--avcodec-hw=videotoolbox"])
        super.init()
        player.delegate = self
    }

    public func play(url: URL, startAt position: TimeInterval = 0) {
        let media = VLCMediaAlias(url: url)
        if position > 0 {
            media.addOption("--start-time=\(Int(position))")
        }
        player.media = media
        player.play()
        state = .loading
    }

    public func pause() {
        player.pause()
        state = .paused
    }

    public func resume() {
        player.play()
        state = .playing
    }

    public func stop() {
        player.stop()
        state = .stopped
    }

    public func seek(to seconds: TimeInterval) {
        player.time = VLCTime(int: Int32(seconds * 1000))
    }

    /// The raw drawable layer — caller embeds this in a `UIView` (iOS/tvOS) or
    /// `NSView` (macOS). Setting this on the underlying player makes VLC
    /// render directly into that view.
    public var drawable: Any? {
        get { player.drawable }
        set { player.drawable = newValue }
    }
}

extension VLCEngine: VLCMediaPlayerDelegate {
    public func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let p = aNotification.object as? VLCMediaPlayerAlias else { return }
        switch p.state {
        case .playing:
            state = .playing
        case .paused:
            state = .paused
        case .stopped, .ended:
            state = .stopped
        case .error:
            state = .error("VLC playback error")
        case .opening, .buffering:
            state = .loading
        default:
            break
        }
    }

    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
        guard let p = aNotification.object as? VLCMediaPlayerAlias else { return }
        position = p.position
        duration = p.media?.length.intValue ?? 0
    }
}
#endif
