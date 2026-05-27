// MARK: - MediaType.swift
// Jellyswarrm — GPL v3 with App Store exception

import Foundation

/// Jellyfin media item types
public enum MediaType: String, Codable, Sendable, CaseIterable {
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
        case .movie, .episode, .audio, .trailer: return true
        default: return false
        }
    }

    public var isContainer: Bool {
        switch self {
        case .series, .season, .collectionFolder, .musicAlbum,
             .musicArtist, .boxSet, .folder, .playlist: return true
        default: return false
        }
    }

    public var displayName: String {
        switch self {
        case .movie: return "Movie"
        case .series: return "TV Series"
        case .episode: return "Episode"
        case .season: return "Season"
        case .collectionFolder: return "Library"
        case .musicAlbum: return "Album"
        case .musicArtist: return "Artist"
        case .audio: return "Song"
        case .book: return "Book"
        case .photo: return "Photo"
        case .trailer: return "Trailer"
        case .boxSet: return "Collection"
        case .folder: return "Folder"
        case .playlist: return "Playlist"
        case .unknown: return "Media"
        }
    }
}

/// Jellyfin image types
public enum ImageType: String, Codable, Sendable {
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
