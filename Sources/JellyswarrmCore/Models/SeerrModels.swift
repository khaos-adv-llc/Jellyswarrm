// MARK: - SeerrModels.swift

// Jellyswarrm — GPL v3 with App Store exception
// Models derived from seerr-open-api.json

import Foundation

// MARK: - Availability / Status

public enum SeerrMediaStatus: Int, Codable, Sendable {
    case unknown = 1
    case pending = 2
    case processing = 3
    case partiallyAvailable = 4
    case available = 5

    public var displayName: String {
        switch self {
        case .unknown: "Unknown"
        case .pending: "Pending"
        case .processing: "Processing"
        case .partiallyAvailable: "Partial"
        case .available: "Available"
        }
    }

    public var isOnServer: Bool {
        self == .available || self == .partiallyAvailable
    }
}

public enum SeerrRequestStatus: Int, Codable, Sendable {
    case pending = 1
    case approved = 2
    case declined = 3
    case available = 4

    public var displayName: String {
        switch self {
        case .pending: "Pending Approval"
        case .approved: "Approved"
        case .declined: "Declined"
        case .available: "Available"
        }
    }
}

// MARK: - Media Info (availability on server)

public struct SeerrMediaInfo: Codable, Sendable, Equatable {
    public let id: Int
    public let mediaType: String
    public let tmdbId: Int?
    public let tvdbId: Int?
    public let imdbId: String?
    public let status: SeerrMediaStatus
    public let status4k: SeerrMediaStatus
    public let jellyfinMediaId: String?
    public let jellyfinMediaId4k: String?
    public let mediaUrl: String?
    public let mediaUrl4k: String?
    public let downloadStatus: [SeerrDownloadStatus]?

    enum CodingKeys: String, CodingKey {
        case id, mediaType, tmdbId, tvdbId, imdbId
        case status, status4k
        case jellyfinMediaId
        case jellyfinMediaId4k
        case mediaUrl, mediaUrl4k
        case downloadStatus
    }
}

public struct SeerrDownloadStatus: Codable, Sendable, Equatable {
    public let externalId: String?
    public let size: Int64?
    public let sizeLeft: Int64?
    public let timeLeft: String?
    public let status: String?
}

// MARK: - Movie Result

public struct SeerrMovieResult: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let mediaType: String
    public let popularity: Double?
    public let posterPath: String?
    public let backdropPath: String?
    public let voteCount: Int?
    public let voteAverage: Double?
    public let genreIds: [Int]?
    public let overview: String?
    public let originalLanguage: String?
    public let originalTitle: String?
    public let title: String
    public let releaseDate: String?
    public let adult: Bool?
    public let video: Bool?
    public let mediaInfo: SeerrMediaInfo?

    public var fullPosterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }

    public var fullBackdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(path)")
    }

    public var releaseYear: String? {
        releaseDate.flatMap { $0.prefix(4) == "" ? nil : String($0.prefix(4)) }
    }

    public var availabilityStatus: SeerrMediaStatus {
        mediaInfo?.status ?? .unknown
    }
}

// MARK: - TV Result

public struct SeerrTvResult: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let mediaType: String
    public let popularity: Double?
    public let posterPath: String?
    public let backdropPath: String?
    public let voteCount: Int?
    public let voteAverage: Double?
    public let genreIds: [Int]?
    public let overview: String?
    public let originalLanguage: String?
    public let originalName: String?
    public let name: String
    public let originCountry: [String]?
    public let firstAirDate: String?
    public let mediaInfo: SeerrMediaInfo?

    public var fullPosterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }

    public var fullBackdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(path)")
    }

    public var releaseYear: String? {
        firstAirDate.flatMap { $0.isEmpty ? nil : String($0.prefix(4)) }
    }

    public var availabilityStatus: SeerrMediaStatus {
        mediaInfo?.status ?? .unknown
    }
}

// MARK: - Unified Search Result

public enum SeerrSearchResult: Codable, Sendable, Identifiable {
    case movie(SeerrMovieResult)
    case tv(SeerrTvResult)
    case person(SeerrPersonResult)

    public var id: Int {
        switch self {
        case let .movie(m): m.id
        case let .tv(t): t.id
        case let .person(p): p.id
        }
    }

    public var title: String {
        switch self {
        case let .movie(m): m.title
        case let .tv(t): t.name
        case let .person(p): p.name
        }
    }

    public var posterPath: String? {
        switch self {
        case let .movie(m): m.posterPath
        case let .tv(t): t.posterPath
        case let .person(p): p.profilePath
        }
    }

    public var mediaInfo: SeerrMediaInfo? {
        switch self {
        case let .movie(m): m.mediaInfo
        case let .tv(t): t.mediaInfo
        case .person: nil
        }
    }

    public var mediaType: String {
        switch self {
        case .movie: "movie"
        case .tv: "tv"
        case .person: "person"
        }
    }

    public var fullPosterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MediaTypeCodingKey.self)
        let mediaType = try container.decode(String.self, forKey: .mediaType)
        switch mediaType {
        case "movie":
            self = try .movie(SeerrMovieResult(from: decoder))
        case "tv":
            self = try .tv(SeerrTvResult(from: decoder))
        case "person":
            self = try .person(SeerrPersonResult(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .mediaType,
                in: container,
                debugDescription: "Unknown mediaType: \(mediaType)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .movie(m): try m.encode(to: encoder)
        case let .tv(t): try t.encode(to: encoder)
        case let .person(p): try p.encode(to: encoder)
        }
    }

    private enum MediaTypeCodingKey: String, CodingKey {
        case mediaType
    }
}

// MARK: - Person Result

public struct SeerrPersonResult: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let profilePath: String?
    public let adult: Bool?
    public let popularity: Double?
    public let knownForDepartment: String?
}

// MARK: - Request

public struct MediaRequest: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let status: SeerrRequestStatus
    public let type: String
    public let requestedBy: SeerrUser?
    public let modifiedBy: SeerrUser?
    public let createdAt: String
    public let updatedAt: String
    public let media: SeerrMediaInfo?
    public let seasons: [RequestedSeason]?
    public let is4k: Bool

    enum CodingKeys: String, CodingKey {
        case id, status, type, requestedBy, modifiedBy
        case createdAt, updatedAt, media, seasons
        case is4k
    }
}

public struct RequestedSeason: Codable, Sendable, Equatable {
    public let id: Int?
    public let name: String?
    public let seasonNumber: Int
    public let status: SeerrMediaStatus?
}

public struct SeerrUser: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let displayName: String
    public let avatar: String?
    public let email: String?
    public let permissions: Int?
    public let requestCount: Int?
}

// MARK: - Request Creation

public struct RequestCreate: Codable, Sendable {
    public let mediaType: String // "movie" or "tv"
    public let mediaId: Int
    public let seasons: [Int]? // for TV: season numbers; nil = all
    public let is4k: Bool

    public init(mediaType: String, mediaId: Int, seasons: [Int]? = nil, is4k: Bool = false) {
        self.mediaType = mediaType
        self.mediaId = mediaId
        self.seasons = seasons
        self.is4k = is4k
    }
}

// MARK: - Paginated Response

public struct SeerrPage<T: Codable & Sendable>: Codable, Sendable {
    public let pageInfo: PageInfo
    public let results: [T]

    public struct PageInfo: Codable, Sendable {
        public let pages: Int
        public let pageSize: Int
        public let results: Int
        public let page: Int
    }
}

// MARK: - Genre

public struct SeerrGenre: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
}

// MARK: - Discover Slider

public struct DiscoverSlider: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let title: String?
    public let type: SliderType
    public let enabled: Bool
    public let isBuiltIn: Bool
    public let data: String?
    public let order: Int

    public enum SliderType: Int, Codable, Sendable {
        case upcomingMovies = 1
        case upcomingTv = 2
        case trending = 3
        case popularMovies = 4
        case popularTv = 5
        case recentlyAddedMovies = 6
        case recentlyAddedTv = 7
        case plex = 8
        case movieGenreSlider = 9
        case tvGenreSlider = 10
        case studio = 11
        case network = 12
        case language = 13
        case keyword = 14
        case unknown = 0

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(Int.self)
            self = SliderType(rawValue: raw) ?? .unknown
        }
    }
}

// MARK: - Status

public struct SeerrStatus: Codable, Sendable {
    public let version: String
    public let commitTag: String?
    public let updateAvailable: Bool?
    public let runtimeEnv: String?
}
