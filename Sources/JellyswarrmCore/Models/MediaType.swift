// MARK: - MediaType.swift

// Jellyswarrm — LGPL-2.1-or-later

import Foundation

/// Jellyfin media item types
public enum MediaType: String, Codable, Sendable, CaseIterable, Hashable {
    case movie = "Movie"
    case series = "Series"
    case episode = "Episode"
    case season = "Season"
    case collectionFolder = "CollectionFolder"
    case musicAlbum = "MusicAlbum"
    case musicArtist = "MusicArtist"
    case audio = "Audio"
    case book = "Book"
    case photo = "Photo"
    case trailer = "Trailer"
    case boxSet = "BoxSet"
    case folder = "Folder"
    case playlist = "Playlist"
    case unknown = "Unknown"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = MediaType(rawValue: raw) ?? .unknown
    }

    public var isPlayable: Bool {
        switch self {
        case .movie, .episode, .audio, .trailer: true
        default: false
        }
    }

    public var isContainer: Bool {
        switch self {
        case .series, .season, .collectionFolder, .musicAlbum,
             .musicArtist, .boxSet, .folder, .playlist: true
        default: false
        }
    }

    public var displayName: String {
        switch self {
        case .movie: "Movie"
        case .series: "TV Series"
        case .episode: "Episode"
        case .season: "Season"
        case .collectionFolder: "Library"
        case .musicAlbum: "Album"
        case .musicArtist: "Artist"
        case .audio: "Song"
        case .book: "Book"
        case .photo: "Photo"
        case .trailer: "Trailer"
        case .boxSet: "Collection"
        case .folder: "Folder"
        case .playlist: "Playlist"
        case .unknown: "Media"
        }
    }
}

/// Jellyfin image types
public enum ImageType: String, Codable, Sendable, Hashable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case thumb = "Thumb"
    case logo = "Logo"
    case banner = "Banner"
    case art = "Art"
    case disc = "Disc"
    case box = "Box"
    case screenshot = "Screenshot"
    case menu = "Menu"
    case chapter = "Chapter"
    case boxRear = "BoxRear"
    case profile = "Profile"
}
