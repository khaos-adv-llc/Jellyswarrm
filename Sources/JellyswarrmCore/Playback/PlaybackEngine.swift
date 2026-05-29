// MARK: - PlaybackEngine.swift

// Jellyswarrm — LGPL-2.1-or-later

import Foundation

/// User-selectable playback engine.
public enum PlaybackEngine: String, CaseIterable, Sendable, Codable {
    case auto         = "auto"
    case avFoundation = "avfoundation"
    case vlc          = "vlc"

    public var displayName: String {
        switch self {
        case .auto:         return "Auto"
        case .avFoundation: return "AVFoundation"
        case .vlc:          return "VLC"
        }
    }

    public var description: String {
        switch self {
        case .auto:
            return "Uses AVFoundation for supported formats, VLC for HDR10, HLG, Dolby Vision Profile 7, and exotic containers"
        case .avFoundation:
            return "Apple's native framework — best for AirPlay, PiP, and Dolby Vision Profile 5/8"
        case .vlc:
            return "VLC engine — broadest format support with accurate HDR color grading"
        }
    }

    /// True when at least one VLC backend (TVVLCKit, MobileVLCKit, VLCKit) is
    /// linked into the current build. The Settings UI gates the VLC engine
    /// option on this, and `PlaybackEngineResolver` falls back to AVFoundation
    /// when false (e.g. pre-`pod install`).
    public static var vlcAvailable: Bool {
        #if canImport(TVVLCKit) || canImport(MobileVLCKit) || canImport(VLCKit)
        return true
        #else
        return false
        #endif
    }
}
