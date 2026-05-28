// MARK: - PlaybackCapabilities.swift

// Jellyswarrm — GPL v3 with App Store exception
// Device-level hardware capability probing used to build a Jellyfin device
// profile that maximises direct play. Apple Silicon and A-series chips have
// dedicated decoders for HEVC, Dolby Vision (HEVC profiles 5/8), HDR10/HLG,
// and (on A17 Pro+) AV1 — we should never ask the server to transcode what
// we can decode natively.

import AVFoundation
import VideoToolbox

public enum PlaybackCapabilities {

    /// Whether the current display can render HDR (HDR10/HLG/DV).
    public static var isHDRCapable: Bool {
        AVPlayer.eligibleForHDRPlayback
    }

    public static var supportsH264: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)
    }

    public static var supportsHEVC: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
    }

    public static var supportsAV1: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    }

    public static var supportsDolbyVision: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_DolbyVisionHEVC)
    }

    public static var supportsHDR10: Bool { supportsHEVC && isHDRCapable }
    public static var supportsHLG: Bool { supportsHEVC && isHDRCapable }
}

/// Audio codec compatibility for AVPlayer direct-stream playback over HTTP.
/// AVPlayer can play many codecs from local files (FLAC, AC-3, E-AC-3) but
/// rejects most non-AAC tracks when streamed inside a remuxed MP4 over the
/// network. Anything outside this set must be transcoded server-side (audio
/// only — the video stream is passed through).
public enum AudioCompatibility {

    /// Audio codecs AVPlayer can play in a remuxed MP4 streamed over HTTP.
    public static let directPlayableCodecs: Set<String> = [
        "aac", "mp3", "mp2", "pcm", "alac", "ac3",
    ]

    public static func isDirectPlayable(_ codec: String?) -> Bool {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return false }
        return directPlayableCodecs.contains(codec)
    }
}
