import Foundation

public enum MediaKind: String, Codable, CaseIterable, Sendable {
    case live, movie, series
}

public enum PlaylistType: String, Codable, Sendable {
    case xtream, m3u
}

/// A saved playlist. The secret part (Xtream password, or the whole M3U address because it can carry login
/// data) is not stored here; the app keeps it in the Keychain under the playlist's id.
public struct Playlist: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var type: PlaylistType
    /// Xtream: server address such as "http://host:8080". M3U: empty.
    public var server: String
    /// Xtream: user name. M3U: empty.
    public var username: String

    public init(id: UUID = UUID(), name: String, type: PlaylistType, server: String = "", username: String = "") {
        self.id = id
        self.name = name
        self.type = type
        self.server = server
        self.username = username
    }
}

public struct XtreamAccount: Hashable, Sendable {
    public var base: String
    public var username: String
    public var password: String

    public init(base: String, username: String, password: String) {
        self.base = base
        self.username = username
        self.password = password
    }
}

public struct MediaCategory: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: MediaKind

    public init(id: String, name: String, kind: MediaKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// A channel, a movie or a series (the container; its episodes are loaded separately).
public struct MediaItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var kind: MediaKind
    public var name: String
    public var logo: String?
    public var categoryID: String
    /// Xtream stream_id / series_id; nil for M3U entries.
    public var streamID: String?
    /// Address to play. nil for a series (episodes carry their own address).
    public var url: String?
    public var containerExt: String?
    public var rating: Double?
    public var year: String?
    public var epgChannelID: String?
    public var hasArchive: Bool

    public init(id: String, kind: MediaKind, name: String, logo: String? = nil, categoryID: String = "",
                streamID: String? = nil, url: String? = nil, containerExt: String? = nil, rating: Double? = nil,
                year: String? = nil, epgChannelID: String? = nil, hasArchive: Bool = false) {
        self.id = id
        self.kind = kind
        self.name = name
        self.logo = logo
        self.categoryID = categoryID
        self.streamID = streamID
        self.url = url
        self.containerExt = containerExt
        self.rating = rating
        self.year = year
        self.epgChannelID = epgChannelID
        self.hasArchive = hasArchive
    }
}

public struct Episode: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var season: Int
    public var number: Int
    public var title: String
    public var url: String
    public var containerExt: String?
    public var plot: String?
    public var image: String?
    public var durationSecs: Int?

    public init(id: String, season: Int, number: Int, title: String, url: String, containerExt: String? = nil,
                plot: String? = nil, image: String? = nil, durationSecs: Int? = nil) {
        self.id = id
        self.season = season
        self.number = number
        self.title = title
        self.url = url
        self.containerExt = containerExt
        self.plot = plot
        self.image = image
        self.durationSecs = durationSecs
    }
}

public struct SeriesDetail: Hashable, Sendable {
    public var plot: String?
    public var cover: String?
    public var genre: String?
    public var episodes: [Episode]

    public init(plot: String? = nil, cover: String? = nil, genre: String? = nil, episodes: [Episode] = []) {
        self.plot = plot
        self.cover = cover
        self.genre = genre
        self.episodes = episodes
    }

    /// Season numbers in ascending order.
    public var seasons: [Int] {
        Array(Set(episodes.map { $0.season })).sorted()
    }

    public func episodes(inSeason season: Int) -> [Episode] {
        episodes.filter { $0.season == season }.sorted { $0.number < $1.number }
    }
}

public struct EPGEntry: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var details: String
    public var start: Date
    public var end: Date

    public init(id: String, title: String, details: String, start: Date, end: Date) {
        self.id = id
        self.title = title
        self.details = details
        self.start = start
        self.end = end
    }
}

/// Stable identifiers that survive app restarts (Swift's hashValue changes per launch).
public enum StableID {
    /// FNV-1a, 64 bit, as 16 hex characters.
    public static func hash(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        let hex = String(h, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }

    public static func item(playlist: UUID, kind: MediaKind, key: String) -> String {
        "\(playlist.uuidString)|\(kind.rawValue)|\(key)"
    }
}
