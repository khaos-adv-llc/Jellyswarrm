// MARK: - PlaybackEngine.swift

// Jellyswarrm — GPL v3 with App Store exception

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
}
