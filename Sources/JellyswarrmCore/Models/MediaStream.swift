// MARK: - MediaStream.swift

// Jellyswarrm — GPL v3 with App Store exception

import Foundation

public struct MediaStream: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let index: Int
    public let codec: String?
    public let codecTag: String?
    public let language: String?
    public let displayLanguage: String?
    public let type: StreamType
    public let isDefault: Bool
    public let isForced: Bool
    public let isExternal: Bool
    public let title: String?
    public let displayTitle: String?
    public let bitRate: Int?
    public let channels: Int?
    public let sampleRate: Int?
    public let width: Int?
    public let height: Int?
    public let videoRange: String?
    public let colorSpace: String?
    public let pixelFormat: String?
    public let level: Int?
    public let profile: String?

    public var id: Int { index }

    enum CodingKeys: String, CodingKey {
        case index = "Index"
        case codec = "Codec"
        case codecTag = "CodecTag"
        case language = "Language"
        case displayLanguage = "DisplayLanguage"
        case type = "Type"
        case isDefault = "IsDefault"
        case isForced = "IsForced"
        case isExternal = "IsExternal"
        case title = "Title"
        case displayTitle = "DisplayTitle"
        case bitRate = "BitRate"
        case channels = "Channels"
        case sampleRate = "SampleRate"
        case width = "Width"
        case height = "Height"
        case videoRange = "VideoRange"
        case colorSpace = "ColorSpace"
        case pixelFormat = "PixelFormat"
        case level = "Level"
        case profile = "Profile"
    }

    public enum StreamType: String, Codable, Sendable, Hashable {
        case audio = "Audio"
        case video = "Video"
        case subtitle = "Subtitle"
        case embeddedImage = "EmbeddedImage"
        case data = "Data"
        case lyric = "Lyric"
    }
}

public struct PlaybackInfo: Codable, Sendable, Hashable {
    public let mediaSources: [MediaSource]

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
    }
}

public struct MediaSource: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String?
    public let path: String?
    public let type: String?
    public let container: String?
    public let size: Int64?
    public let bitrate: Int?
    public let runTimeTicks: Int64?
    public let isRemote: Bool
    public let supportsDirectPlay: Bool
    public let supportsDirectStream: Bool
    public let supportsTranscoding: Bool
    public let transcodingUrl: String?
    public let directStreamUrl: String?
    public let mediaStreams: [MediaStream]?
    public let defaultAudioStreamIndex: Int?
    public let defaultSubtitleStreamIndex: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case path = "Path"
        case type = "Type"
        case container = "Container"
        case size = "Size"
        case bitrate = "Bitrate"
        case runTimeTicks = "RunTimeTicks"
        case isRemote = "IsRemote"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case transcodingUrl = "TranscodingUrl"
        case directStreamUrl = "DirectStreamUrl"
        case mediaStreams = "MediaStreams"
        case defaultAudioStreamIndex = "DefaultAudioStreamIndex"
        case defaultSubtitleStreamIndex = "DefaultSubtitleStreamIndex"
    }
}
