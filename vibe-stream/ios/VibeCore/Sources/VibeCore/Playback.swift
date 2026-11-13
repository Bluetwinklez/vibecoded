import Foundation

/// What the built-in iOS player (AVPlayer) can open, and how to get a playable address for the rest.
public enum Playback {
    /// Containers AVPlayer plays. Notably missing: mkv, avi and raw MPEG-TS (.ts), which IPTV providers use a lot.
    public static let nativeExtensions: Set<String> = ["m3u8", "mp4", "m4v", "mov", "mp3", "aac", "m4a"]

    /// Lower-case file extension of the path of [url] (ignores the query), nil = none.
    public static func fileExtension(of url: String) -> String? {
        var path = url
        if let q = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<q]) }
        // Skip "scheme://host" so that the dot of the host name is never taken for an extension
        if let scheme = path.range(of: "://") { path = String(path[scheme.upperBound...]) }
        guard let lastSlash = path.lastIndex(of: "/") else { return nil }
        let name = path[path.index(after: lastSlash)...]
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = name[name.index(after: dot)...].lowercased()
        guard !ext.isEmpty, ext.count <= 5, ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return ext
    }

    /// true = AVPlayer can be expected to play it. An address without an extension is unknown and worth a try.
    public static func isNativelyPlayable(_ url: String) -> Bool {
        guard let ext = fileExtension(of: url) else { return true }
        return nativeExtensions.contains(ext)
    }

    /// The HLS form of an Xtream live address, or nil if [url] does not look like one.
    ///   http://host/live/user/pass/123.ts -> http://host/live/user/pass/123.m3u8
    ///   http://host/user/pass/123         -> http://host/live/user/pass/123.m3u8
    public static func hlsVariant(ofLive url: String) -> String? {
        guard var c = URLComponents(string: url), c.host != nil else { return nil }
        var parts = c.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let last = parts.last else { return nil }
        var id = last
        if let dot = last.lastIndex(of: ".") {
            let ext = last[last.index(after: dot)...].lowercased()
            guard ext == "ts" else { return nil }
            id = String(last[..<dot])
        }
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        if parts.count == 4, parts[0].lowercased() == "live" {
            parts[3] = id + ".m3u8"
        } else if parts.count == 3 {
            parts = ["live", parts[0], parts[1], id + ".m3u8"]
        } else {
            return nil
        }
        c.percentEncodedPath = "/" + parts.joined(separator: "/")
        return c.string
    }

    /// Addresses to try in order. Empty = nothing AVPlayer can open (offer an external player instead).
    public static func candidates(for url: String, kind: MediaKind) -> [String] {
        var out: [String] = []
        if kind == .live, let hls = hlsVariant(ofLive: url) { out.append(hls) }
        if isNativelyPlayable(url), !out.contains(url) { out.append(url) }
        return out
    }

    /// Link that opens [url] in the VLC app (which plays mkv, avi and MPEG-TS).
    public static func vlcURL(for url: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = url.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "vlc-x-callback://x-callback-url/stream?url=" + encoded)
    }
}

/// Search over item names: case- and accent-insensitive, every word of the query must occur.
public enum Search {
    public static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
            .lowercased()
    }

    public static func tokens(_ query: String) -> [String] {
        normalize(query).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    public static func filter(_ items: [MediaItem], query: String, limit: Int = 300) -> [MediaItem] {
        let words = tokens(query)
        guard !words.isEmpty else { return [] }
        var prefix: [MediaItem] = []
        var rest: [MediaItem] = []
        for item in items {
            let name = normalize(item.name)
            guard words.allSatisfy({ name.contains($0) }) else { continue }
            if name.hasPrefix(words[0]) { prefix.append(item) } else { rest.append(item) }
            if prefix.count >= limit { break }
        }
        return Array((prefix + rest).prefix(limit))
    }
}
