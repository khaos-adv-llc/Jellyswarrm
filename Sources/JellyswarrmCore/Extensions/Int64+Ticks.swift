// MARK: - Int64+Ticks.swift

// Jellyswarrm — GPL v3 with App Store exception
// Jellyfin stores durations and positions as 100-nanosecond ticks

import Foundation

public extension Int64 {
    /// Convert Jellyfin ticks (100ns intervals) to seconds
    var ticksToSeconds: Double {
        Double(self) / 10_000_000.0
    }

    /// Convert Jellyfin ticks to a formatted duration string (e.g. "1h 23m")
    var ticksToDurationString: String {
        let totalSeconds = Int(ticksToSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    /// Convert Jellyfin ticks to a playback-style string (e.g. "1:23:45")
    var ticksToPlaybackString: String {
        let totalSeconds = Int(ticksToSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

public extension Double {
    /// Convert seconds to Jellyfin ticks
    var secondsToTicks: Int64 {
        Int64(self * 10_000_000.0)
    }
}
