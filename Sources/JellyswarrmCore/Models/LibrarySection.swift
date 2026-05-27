// MARK: - LibrarySection.swift

// Jellyswarrm — GPL v3 with App Store exception

import Foundation

/// A top-level Jellyfin library (Movies, TV Shows, Music, etc.)
public struct LibrarySection: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let collectionType: CollectionType?
    public let primaryImageTag: String?
    public let childCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case collectionType = "CollectionType"
        case primaryImageTag = "PrimaryImageTag"
        case childCount = "ChildCount"
    }

    public enum CollectionType: String, Codable, Sendable {
        case movies
        case tvshows
        case music
        case musicvideos
        case homevideos
        case boxsets
        case books
        case photos
        case livetv
        case playlists
        case folders
        case unknown

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            self = CollectionType(rawValue: raw.lowercased()) ?? .unknown
        }

        public var systemImageName: String {
            switch self {
            case .movies: "film"
            case .tvshows: "tv"
            case .music: "music.note"
            case .musicvideos: "music.note.tv"
            case .homevideos: "video"
            case .boxsets: "square.stack"
            case .books: "book"
            case .photos: "photo"
            case .livetv: "antenna.radiowaves.left.and.right"
            case .playlists: "list.bullet"
            case .folders: "folder"
            case .unknown: "questionmark.folder"
            }
        }
    }
}
