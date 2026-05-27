// MARK: - UserData.swift

// Jellyswarrm — GPL v3 with App Store exception

import Foundation

/// Tracks per-user playback state for a media item
public struct UserData: Codable, Sendable, Equatable {
    public let playbackPositionTicks: Int64
    public let playCount: Int
    public let isFavorite: Bool
    public let played: Bool
    public let key: String
    public let lastPlayedDate: Date?
    public let playedPercentage: Double?
    public let unplayedItemCount: Int?

    public init(
        playbackPositionTicks: Int64 = 0,
        playCount: Int = 0,
        isFavorite: Bool = false,
        played: Bool = false,
        key: String = "",
        lastPlayedDate: Date? = nil,
        playedPercentage: Double? = nil,
        unplayedItemCount: Int? = nil
    ) {
        self.playbackPositionTicks = playbackPositionTicks
        self.playCount = playCount
        self.isFavorite = isFavorite
        self.played = played
        self.key = key
        self.lastPlayedDate = lastPlayedDate
        self.playedPercentage = playedPercentage
        self.unplayedItemCount = unplayedItemCount
    }

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playCount = "PlayCount"
        case isFavorite = "IsFavorite"
        case played = "Played"
        case key = "Key"
        case lastPlayedDate = "LastPlayedDate"
        case playedPercentage = "PlayedPercentage"
        case unplayedItemCount = "UnplayedItemCount"
    }

    /// Progress from 0.0 to 1.0
    public var normalizedProgress: Double {
        playedPercentage.map { $0 / 100.0 } ?? 0.0
    }

    public var hasProgress: Bool {
        playbackPositionTicks > 0
    }
}
