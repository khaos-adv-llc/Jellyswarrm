// MARK: - PlaybackEngineResolver.swift

// Jellyswarrm — GPL v3 with App Store exception

import Foundation

public enum PlaybackEngineResolver {
    /// Determines which engine to actually use given user preference and detected format.
    public static func resolve(
        preference: PlaybackEngine,
        hdrFormat: HDRFormat,
        container: String,
        audioCodec: String
    ) -> PlaybackEngine {
        switch preference {
        case .avFoundation: return .avFoundation
        case .vlc:          return .vlc
        case .auto:
            return autoResolve(hdrFormat: hdrFormat, container: container, audioCodec: audioCodec)
        }
    }

    private static func autoResolve(
        hdrFormat: HDRFormat,
        container _: String,
        audioCodec: String
    ) -> PlaybackEngine {
        // VLC for formats AVFoundation can't handle well:
        // - HDR10 (PQ) — VLC has better tone mapping than the current Metal shader
        // - HLG — VLC handles correctly
        // - Dolby Vision Profile 7 (dual-layer, not natively supported by Apple)
        // - TrueHD, DTS-HD MA audio codecs (Apple's stack can't decode)
        let vlcAudioCodecs = ["truehd", "dts", "dtshd", "dts-hd", "mlp"]
        let needsVLC = hdrFormat == .hdr10
            || hdrFormat == .hlg
            || vlcAudioCodecs.contains(audioCodec.lowercased())

        return needsVLC ? .vlc : .avFoundation
    }
}
