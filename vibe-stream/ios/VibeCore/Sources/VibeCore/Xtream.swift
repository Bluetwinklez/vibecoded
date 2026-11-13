import Foundation

/// Xtream Codes API (player_api.php): address building and tolerant parsing of the answers.
/// Providers are inconsistent (numbers as strings, missing fields, arrays instead of objects), so the
/// parsers read loosely typed JSON instead of fixed Codable structs.
public enum Xtream {
    // MARK: - Addresses

    /// "server.tld:8080" -> "http://server.tld:8080"; removes a trailing slash and a pasted "/player_api.php…" or
    /// "/get.php…" part. nil = not a usable address.
    public static func normalizeServer(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") { s = "http://" + s }
        for marker in ["/player_api.php", "/get.php", "/xmltv.php", "/panel_api.php"] {
            if let r = s.range(of: marker, options: .caseInsensitive) { s = String(s[..<r.lowerBound]) }
        }
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        while s.hasSuffix("/") { s.removeLast() }
        guard let c = URLComponents(string: s), c.host?.isEmpty == false else { return nil }
        return s
    }

    /// Login data from a pasted "…/get.php?username=…&password=…" (or player_api.php) address.
    public static func account(fromURL url: String) -> XtreamAccount? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: trimmed), let host = c.host, !host.isEmpty else { return nil }
        let path = c.path.lowercased()
        guard path.hasSuffix("/get.php") || path.hasSuffix("/player_api.php") else { return nil }
        var user: String?
        var pass: String?
        for item in c.queryItems ?? [] {
            switch item.name.lowercased() {
            case "username": user = item.value
            case "password": pass = item.value
            default: break
            }
        }
        guard let u = user, !u.isEmpty, let p = pass, !p.isEmpty else { return nil }
        guard let base = normalizeServer(trimmed) else { return nil }
        return XtreamAccount(base: base, username: u, password: p)
    }

    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func queryEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? s
    }

    /// One path segment; providers expect plain text, so only special characters are encoded.
    public static func pathPart(_ s: String) -> String {
        queryEncode(s)
    }

    public static func apiURL(_ a: XtreamAccount, action: String? = nil, params: [(String, String)] = []) -> URL? {
        var s = "\(a.base)/player_api.php?username=\(queryEncode(a.username))&password=\(queryEncode(a.password))"
        if let action = action { s += "&action=\(queryEncode(action))" }
        for (k, v) in params { s += "&\(queryEncode(k))=\(queryEncode(v))" }
        return URL(string: s)
    }

    /// Live address. iOS cannot play raw MPEG-TS, so the HLS form (.m3u8) is the default.
    public static func liveURL(_ a: XtreamAccount, id: String, hls: Bool = true) -> String {
        "\(a.base)/live/\(pathPart(a.username))/\(pathPart(a.password))/\(id).\(hls ? "m3u8" : "ts")"
    }

    private static func cleanExt(_ ext: String?, default def: String) -> String {
        guard var e = ext?.trimmingCharacters(in: .whitespaces), !e.isEmpty else { return def }
        while e.hasPrefix(".") { e.removeFirst() }
        let ok = !e.isEmpty && e.count <= 5 && e.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return ok ? e.lowercased() : def
    }

    public static func movieURL(_ a: XtreamAccount, id: String, ext: String?) -> String {
        "\(a.base)/movie/\(pathPart(a.username))/\(pathPart(a.password))/\(id).\(cleanExt(ext, default: "mp4"))"
    }

    public static func episodeURL(_ a: XtreamAccount, id: String, ext: String?) -> String {
        "\(a.base)/series/\(pathPart(a.username))/\(pathPart(a.password))/\(id).\(cleanExt(ext, default: "mp4"))"
    }

    // MARK: - Loose JSON helpers

    /// A JSON true/false arrives as an NSNumber of type char ("c") on Apple platforms and on Linux;
    /// JSON numbers never use that type.
    static func isBool(_ n: NSNumber) -> Bool {
        String(cString: n.objCType) == "c"
    }

    static func string(_ v: Any?) -> String? {
        switch v {
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let n as NSNumber:
            // A JSON boolean arrives as NSNumber too; "1"/"0" is what the callers expect for those.
            if isBool(n) { return n.boolValue ? "1" : "0" }
            return n.stringValue
        default:
            return nil
        }
    }

    static func int(_ v: Any?) -> Int? {
        if let n = v as? NSNumber, !isBool(n) { return n.intValue }
        guard let s = string(v) else { return nil }
        if let i = Int(s) { return i }
        if let d = Double(s) { return Int(d) }
        return nil
    }

    static func double(_ v: Any?) -> Double? {
        if let n = v as? NSNumber, !isBool(n) { return n.doubleValue }
        guard let s = string(v) else { return nil }
        return Double(s.replacingOccurrences(of: ",", with: "."))
    }

    static func httpURL(_ v: Any?) -> String? {
        guard let s = string(v), s.lowercased().hasPrefix("http") else { return nil }
        return s
    }

    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
    }

    static func array(_ data: Data) -> [[String: Any]] {
        guard let any = try? JSONSerialization.jsonObject(with: data, options: []) else { return [] }
        if let list = any as? [[String: Any]] { return list }
        // Some panels answer with an object keyed by index instead of a list
        if let dict = any as? [String: Any] {
            return dict.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }.compactMap { dict[$0] as? [String: Any] }
        }
        return []
    }

    private static func digitsID(_ v: Any?) -> String? {
        guard let s = string(v), !s.isEmpty, s.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return s
    }

    // MARK: - Login

    public struct AuthInfo: Hashable, Sendable {
        /// true = login accepted, false = refused, nil = the answer could not be read.
        public var ok: Bool?
        public var status: String?
        public var message: String?
        public var expires: Date?
        public var maxConnections: Int?
        public var activeConnections: Int?

        public init(ok: Bool?, status: String? = nil, message: String? = nil, expires: Date? = nil,
                    maxConnections: Int? = nil, activeConnections: Int? = nil) {
            self.ok = ok
            self.status = status
            self.message = message
            self.expires = expires
            self.maxConnections = maxConnections
            self.activeConnections = activeConnections
        }
    }

    public static func parseAuth(_ data: Data) -> AuthInfo {
        guard let root = object(data), let info = root["user_info"] as? [String: Any] else { return AuthInfo(ok: nil) }
        let auth = string(info["auth"])
        let status = string(info["status"])
        var ok: Bool?
        if auth == "0" {
            ok = false
        } else if let st = status?.lowercased(), ["disabled", "banned", "expired"].contains(st) {
            ok = false
        } else if auth == "1" {
            ok = true
        }
        var expires: Date?
        if let ts = int(info["exp_date"]), ts > 0 { expires = Date(timeIntervalSince1970: TimeInterval(ts)) }
        return AuthInfo(ok: ok, status: status, message: string(info["message"]), expires: expires,
                        maxConnections: int(info["max_connections"]), activeConnections: int(info["active_cons"]))
    }

    // MARK: - Lists

    public static func action(forCategoriesOf kind: MediaKind) -> String {
        switch kind {
        case .live: return "get_live_categories"
        case .movie: return "get_vod_categories"
        case .series: return "get_series_categories"
        }
    }

    public static func action(forItemsOf kind: MediaKind) -> String {
        switch kind {
        case .live: return "get_live_streams"
        case .movie: return "get_vod_streams"
        case .series: return "get_series"
        }
    }

    public static func parseCategories(_ data: Data, kind: MediaKind) -> [MediaCategory] {
        array(data).compactMap { (o: [String: Any]) -> MediaCategory? in
            guard let id = string(o["category_id"]), let name = string(o["category_name"]) else { return nil }
            return MediaCategory(id: id, name: name, kind: kind)
        }
    }

    private static let yearInName = try! NSRegularExpression(pattern: #"[\(\[]((?:19|20)\d{2})[\)\]]"#)

    private static func year(_ o: [String: Any], name: String) -> String? {
        let range = NSRange(name.startIndex..., in: name)
        if let m = yearInName.firstMatch(in: name, range: range), let r = Range(m.range(at: 1), in: name) {
            return String(name[r])
        }
        for key in ["year", "releaseDate", "release_date", "releasedate"] {
            if let s = string(o[key]), s.count >= 4 {
                let y = String(s.prefix(4))
                if y.hasPrefix("19") || y.hasPrefix("20"), Int(y) != nil { return y }
            }
        }
        return nil
    }

    private static func rating(_ o: [String: Any]) -> Double? {
        guard let r = double(o["rating"]), r > 0, r <= 10 else { return nil }
        return r
    }

    public static func parseItems(_ data: Data, kind: MediaKind, account a: XtreamAccount, playlist: UUID) -> [MediaItem] {
        array(data).compactMap { (o: [String: Any]) -> MediaItem? in
            guard let name = string(o["name"]) else { return nil }
            let category = string(o["category_id"]) ?? ""
            switch kind {
            case .live:
                guard let id = digitsID(o["stream_id"]) else { return nil }
                return MediaItem(id: StableID.item(playlist: playlist, kind: .live, key: id), kind: .live, name: name,
                                 logo: httpURL(o["stream_icon"]), categoryID: category, streamID: id,
                                 url: liveURL(a, id: id), containerExt: "m3u8",
                                 epgChannelID: string(o["epg_channel_id"]), hasArchive: string(o["tv_archive"]) == "1")
            case .movie:
                guard let id = digitsID(o["stream_id"]) else { return nil }
                let ext = string(o["container_extension"])
                return MediaItem(id: StableID.item(playlist: playlist, kind: .movie, key: id), kind: .movie, name: name,
                                 logo: httpURL(o["stream_icon"]), categoryID: category, streamID: id,
                                 url: movieURL(a, id: id, ext: ext), containerExt: ext?.lowercased(),
                                 rating: rating(o), year: year(o, name: name))
            case .series:
                guard let id = digitsID(o["series_id"]) else { return nil }
                return MediaItem(id: StableID.item(playlist: playlist, kind: .series, key: id), kind: .series, name: name,
                                 logo: httpURL(o["cover"]), categoryID: category, streamID: id,
                                 rating: rating(o), year: year(o, name: name))
            }
        }
    }

    // MARK: - Series

    public static func parseSeriesInfo(_ data: Data, account a: XtreamAccount) -> SeriesDetail {
        guard let root = object(data) else { return SeriesDetail() }
        let info = root["info"] as? [String: Any] ?? [:]
        var episodes: [Episode] = []

        func add(_ list: [Any], seasonKey: Int?) {
            for case let o as [String: Any] in list {
                guard let id = digitsID(o["id"]) else { continue }
                let season = int(o["season"]) ?? seasonKey ?? 1
                guard let num = int(o["episode_num"]), (0...99).contains(season), (0...9999).contains(num) else { continue }
                let extra = o["info"] as? [String: Any] ?? [:]
                let ext = string(o["container_extension"])
                let title = string(o["title"]) ?? "S\(season) E\(num)"
                episodes.append(Episode(id: id, season: season, number: num, title: title,
                                        url: episodeURL(a, id: id, ext: ext), containerExt: ext?.lowercased(),
                                        plot: string(extra["plot"]), image: httpURL(extra["movie_image"]),
                                        durationSecs: int(extra["duration_secs"])))
            }
        }

        if let bySeason = root["episodes"] as? [String: Any] {
            for (key, value) in bySeason {
                if let list = value as? [Any] { add(list, seasonKey: Int(key)) }
            }
        } else if let seasons = root["episodes"] as? [Any] {
            for (index, value) in seasons.enumerated() {
                if let list = value as? [Any] { add(list, seasonKey: index + 1) }
            }
        }
        episodes.sort { ($0.season, $0.number) < ($1.season, $1.number) }
        return SeriesDetail(plot: string(info["plot"]), cover: httpURL(info["cover"]), genre: string(info["genre"]),
                            episodes: episodes)
    }

    // MARK: - TV guide

    private static func decodeBase64Text(_ v: Any?) -> String {
        guard let s = string(v) else { return "" }
        if let d = Data(base64Encoded: s, options: .ignoreUnknownCharacters), let t = String(data: d, encoding: .utf8) {
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    /// Answer of get_short_epg / get_simple_data_table: titles and descriptions are base64 encoded.
    public static func parseEPG(_ data: Data) -> [EPGEntry] {
        guard let root = object(data), let list = root["epg_listings"] as? [Any] else { return [] }
        var out: [EPGEntry] = []
        for case let o as [String: Any] in list {
            guard let start = int(o["start_timestamp"]), let stop = int(o["stop_timestamp"]), stop > start else { continue }
            let title = decodeBase64Text(o["title"])
            if title.isEmpty { continue }
            let id = string(o["id"]) ?? "\(start)"
            out.append(EPGEntry(id: "\(id)-\(start)", title: title, details: decodeBase64Text(o["description"]),
                                start: Date(timeIntervalSince1970: TimeInterval(start)),
                                end: Date(timeIntervalSince1970: TimeInterval(stop))))
        }
        return out.sorted { $0.start < $1.start }
    }
}
