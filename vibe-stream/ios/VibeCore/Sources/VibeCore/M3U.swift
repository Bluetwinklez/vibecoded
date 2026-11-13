import Foundation

/// One entry of an M3U playlist.
public struct M3UEntry: Hashable, Sendable {
    public var name: String
    public var url: String
    public var logo: String?
    public var group: String
    public var tvgID: String?

    public init(name: String, url: String, logo: String? = nil, group: String = "", tvgID: String? = nil) {
        self.name = name
        self.url = url
        self.logo = logo
        self.group = group
        self.tvgID = tvgID
    }
}

/// Line-by-line M3U parser, so a large playlist never has to sit in memory as one string.
public struct M3UParser {
    public private(set) var epgURL: String?
    private var pendingName: String?
    private var pendingAttributes: [String: String] = [:]
    private var pendingGroup: String?

    public init() {}

    private static let attribute = try! NSRegularExpression(pattern: #"([A-Za-z0-9_-]+)="([^"]*)""#)

    /// Feeds one line; returns an entry when the line completes one (the address line after #EXTINF).
    public mutating func feed(_ rawLine: String) -> M3UEntry? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.unicodeScalars.first == "\u{FEFF}" { line = String(String.UnicodeScalarView(line.unicodeScalars.dropFirst())) }
        if line.isEmpty { return nil }

        if line.hasPrefix("#EXTM3U") {
            let attrs = Self.attributes(in: line)
            epgURL = attrs["url-tvg"] ?? attrs["x-tvg-url"] ?? epgURL
            return nil
        }
        if line.hasPrefix("#EXTINF") {
            let (attrs, name) = Self.parseInfo(line)
            pendingAttributes = attrs
            pendingName = name
            return nil
        }
        if line.hasPrefix("#EXTGRP:") {
            pendingGroup = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        if line.hasPrefix("#") { return nil }

        // An address line. Without a preceding #EXTINF it is still a playable entry (plain list of links).
        defer {
            pendingName = nil
            pendingAttributes = [:]
            pendingGroup = nil
        }
        guard line.contains("://") else { return nil }
        let name = pendingName?.isEmpty == false ? pendingName! : Self.fallbackName(for: line)
        let group = pendingAttributes["group-title"].flatMap { $0.isEmpty ? nil : $0 } ?? pendingGroup ?? ""
        let logo = pendingAttributes["tvg-logo"].flatMap { $0.lowercased().hasPrefix("http") ? $0 : nil }
        let tvgID = pendingAttributes["tvg-id"].flatMap { $0.isEmpty ? nil : $0 }
        return M3UEntry(name: name, url: line, logo: logo, group: group, tvgID: tvgID)
    }

    public static func parse(_ text: String) -> (entries: [M3UEntry], epgURL: String?) {
        var parser = M3UParser()
        var out: [M3UEntry] = []
        for line in text.split(whereSeparator: { $0.isNewline }) {
            if let e = parser.feed(String(line)) { out.append(e) }
        }
        return (out, parser.epgURL)
    }

    static func attributes(in line: String) -> [String: String] {
        var out: [String: String] = [:]
        let ns = line as NSString
        for m in attribute.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            out[ns.substring(with: m.range(at: 1)).lowercased()] = ns.substring(with: m.range(at: 2))
        }
        return out
    }

    /// Attributes and display name of an "#EXTINF:-1 key="value" …,Name" line.
    /// The name starts after the first comma that follows the last attribute, so commas inside quoted
    /// values and inside the name itself are kept.
    static func parseInfo(_ line: String) -> ([String: String], String) {
        let ns = line as NSString
        let matches = attribute.matches(in: line, range: NSRange(location: 0, length: ns.length))
        var attrs: [String: String] = [:]
        var searchFrom = 0
        for m in matches {
            attrs[ns.substring(with: m.range(at: 1)).lowercased()] = ns.substring(with: m.range(at: 2))
            searchFrom = max(searchFrom, m.range.location + m.range.length)
        }
        let comma = ns.range(of: ",", options: [], range: NSRange(location: searchFrom, length: ns.length - searchFrom))
        var name = ""
        if comma.location != NSNotFound {
            name = ns.substring(from: comma.location + 1).trimmingCharacters(in: .whitespaces)
        }
        if name.isEmpty, let n = attrs["tvg-name"] { name = n }
        return (attrs, name)
    }

    static func fallbackName(for url: String) -> String {
        let path = url.split(separator: "?").first.map(String.init) ?? url
        let last = path.split(separator: "/").last.map(String.init) ?? url
        return last.removingPercentEncoding ?? last
    }
}

/// Sorts M3U entries into live channels, movies and series.
public enum M3ULibrary {
    private static let videoFileExtensions: Set<String> = ["mp4", "mkv", "avi", "mov", "m4v", "wmv", "flv", "mpg", "mpeg", "webm"]
    private static let episodeTag = try! NSRegularExpression(pattern: #"^(.*?)[\s._-]*S(\d{1,2})\s*[._-]?\s*E(\d{1,4})"#, options: [.caseInsensitive])

    public static func kind(ofURL url: String, name: String) -> MediaKind {
        let lower = url.lowercased()
        if lower.contains("/series/") { return .series }
        if lower.contains("/movie/") { return .movie }
        if let ext = Playback.fileExtension(of: url), videoFileExtensions.contains(ext) {
            return episode(in: name) != nil ? .series : .movie
        }
        return .live
    }

    /// "Show Name S02E05 …" -> ("Show Name", 2, 5)
    public static func episode(in name: String) -> (series: String, season: Int, number: Int)? {
        let ns = name as NSString
        guard let m = episodeTag.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let series = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        guard !series.isEmpty, let s = Int(ns.substring(with: m.range(at: 2))), let e = Int(ns.substring(with: m.range(at: 3))) else { return nil }
        return (series, s, e)
    }

    public struct Library: Sendable {
        public var categories: [MediaKind: [MediaCategory]] = [:]
        public var items: [MediaKind: [MediaItem]] = [:]
        /// Episodes of a series, keyed by the id of the series item.
        public var episodes: [String: [Episode]] = [:]
        public var epgURL: String?

        public init() {}
    }

    public static func build(_ entries: [M3UEntry], playlist: UUID, epgURL: String? = nil) -> Library {
        var result = Library()
        result.epgURL = epgURL
        var categoryOrder: [MediaKind: [String]] = [:]
        var seenCategory: [MediaKind: Set<String>] = [:]
        var seriesIndex: [String: Int] = [:]

        func note(_ kind: MediaKind, _ group: String) -> String {
            let g = group.isEmpty ? "–" : group
            if seenCategory[kind, default: []].insert(g).inserted { categoryOrder[kind, default: []].append(g) }
            return g
        }

        for e in entries {
            let kind = Self.kind(ofURL: e.url, name: e.name)
            let group = note(kind, e.group)
            switch kind {
            case .live, .movie:
                let id = StableID.item(playlist: playlist, kind: kind, key: StableID.hash(e.url))
                result.items[kind, default: []].append(
                    MediaItem(id: id, kind: kind, name: e.name, logo: e.logo, categoryID: group, url: e.url,
                              containerExt: Playback.fileExtension(of: e.url), epgChannelID: e.tvgID))
            case .series:
                let parsed = episode(in: e.name)
                let seriesName = parsed?.series ?? e.name
                let key = group + "\u{1}" + seriesName.lowercased()
                let seriesID = StableID.item(playlist: playlist, kind: .series, key: StableID.hash(key))
                if seriesIndex[key] == nil {
                    seriesIndex[key] = result.items[.series, default: []].count
                    result.items[.series, default: []].append(
                        MediaItem(id: seriesID, kind: .series, name: seriesName, logo: e.logo, categoryID: group))
                }
                let season = parsed?.season ?? 1
                let number = parsed?.number ?? ((result.episodes[seriesID]?.count ?? 0) + 1)
                result.episodes[seriesID, default: []].append(
                    Episode(id: StableID.hash(e.url), season: season, number: number, title: e.name, url: e.url,
                            containerExt: Playback.fileExtension(of: e.url)))
            }
        }
        for kind in MediaKind.allCases {
            result.categories[kind] = (categoryOrder[kind] ?? []).map { MediaCategory(id: $0, name: $0, kind: kind) }
        }
        return result
    }
}
