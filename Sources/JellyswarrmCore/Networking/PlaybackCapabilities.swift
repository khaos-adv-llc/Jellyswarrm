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
