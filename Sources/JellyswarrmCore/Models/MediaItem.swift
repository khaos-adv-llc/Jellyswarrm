// MARK: - MediaItem.swift

// Jellyswarrm — LGPL-2.1-or-later

import Foundation

/// A Jellyfin media item — covers movies, series, episodes, seasons, and library folders
public struct MediaItem: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let sortName: String?
    public let type: MediaType
    public let overview: String?
    public let productionYear: Int?
    public let premiereDate: Date?
    public let endDate: Date?
    public let officialRating: String?
    public let communityRating: Double?
    public let criticRating: Double?
    public let runtimeTicks: Int64?
    public let parentId: String?
    public let seriesId: String?
    public let seriesName: String?
    public let seriesPrimaryImageTag: String?
    public let seasonId: String?
    public let seasonName: String?
    public let indexNumber: Int? // episode number
    public let parentIndexNumber: Int? // season number
    public let userData: UserData?
    public let imageBlurHashes: [String: [String: String]]?
    public let backdropImageTags: [String]?
    public let imageTags: [String: String]?
    public let mediaStreams: [MediaStream]?
    public let genreItems: [NameId]?
    public let studios: [NameId]?
    public let people: [PersonInfo]?
    public let taglines: [String]?
    public let childCount: Int?
    public let recursiveItemCount: Int?
    public let collectionType: String?
    public let locationType: String?
    public let videoType: String?
    public let container: String?
    public let chapters: [ChapterInfo]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case sortName = "SortName"
        case type = "Type"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case premiereDate = "PremiereDate"
        case endDate = "EndDate"
        case officialRating = "OfficialRating"
        case communityRating = "CommunityRating"
        case criticRating = "CriticRating"
        case runtimeTicks = "RunTimeTicks"
        case parentId = "ParentId"
        case seriesId = "SeriesId"
        case seriesName = "SeriesName"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case seasonId = "SeasonId"
        case seasonName = "SeasonName"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case userData = "UserData"
        case imageBlurHashes = "ImageBlurHashes"
        case backdropImageTags = "BackdropImageTags"
        case imageTags = "ImageTags"
        case mediaStreams = "MediaStreams"
        case genreItems = "GenreItems"
        case studios = "Studios"
        case people = "People"
        case taglines = "Taglines"
        case childCount = "ChildCount"
        case recursiveItemCount = "RecursiveItemCount"
        case collectionType = "CollectionType"
        case locationType = "LocationType"
        case videoType = "VideoType"
        case container = "Container"
        case chapters = "Chapters"
    }

    // MARK: - Computed helpers

    public var runtimeSeconds: Double? {
        guard let ticks = runtimeTicks else { return nil }
        return Double(ticks) / 10_000_000.0
    }

    public var displayTitle: String {
        switch type {
        case .episode:
            let s = parentIndexNumber.map { "S\(String(format: "%02d", $0))" } ?? ""
            let e = indexNumber.map { "E\(String(format: "%02d", $0))" } ?? ""
            let prefix = [s, e].filter { !$0.isEmpty }.joined()
            return prefix.isEmpty ? name : "\(prefix) — \(name)"
        default:
            return name
        }
    }

    public var primaryImageTag: String? {
        imageTags?["Primary"]
    }

    public var thumbImageTag: String? {
        imageTags?["Thumb"]
    }

    public var logoImageTag: String? {
        imageTags?["Logo"]
    }

    public var firstBackdropTag: String? {
        backdropImageTags?.first
    }

    public var isPlayed: Bool { userData?.played ?? false }
    public var playedPercentage: Double? { userData?.playedPercentage }
}

// MARK: - Supporting Types

public struct NameId: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

public struct ChapterInfo: Codable, Sendable, Equatable, Hashable {
    public let name: String?
    public let startPositionTicks: Int64?
    public let imageTag: String?
    public let imagePath: String?

    public init(name: String?, startPositionTicks: Int64?, imageTag: String? = nil, imagePath: String? = nil) {
        self.name = name
        self.startPositionTicks = startPositionTicks
        self.imageTag = imageTag
        self.imagePath = imagePath
    }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case startPositionTicks = "StartPositionTicks"
        case imageTag = "ImageTag"
        case imagePath = "ImagePath"
    }
}

public struct PersonInfo: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let type: String?
    public let role: String?
    public let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case role = "Role"
        case primaryImageTag = "PrimaryImageTag"
    }
}

// MARK: - API Response Wrappers

public struct ItemsResponse<T: Codable & Sendable>: Codable, Sendable {
    public let items: [T]
    public let totalRecordCount: Int
    public let startIndex: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }
}

public struct AuthResponse: Codable, Sendable {
    public let accessToken: String
    public let serverId: String
    public let user: JellyfinUser

    /// Convenience accessor — Jellyfin returns the user ID inside the User object,
    /// not as a top-level field.
    public var userId: String { user.id }

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case serverId = "ServerId"
        case user = "User"
    }
}

public struct JellyfinUser: Codable, Sendable {
    public let id: String
    public let name: String
    public let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case primaryImageTag = "PrimaryImageTag"
    }
}
