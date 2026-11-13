import Foundation
import VibeCore

enum ContentError: LocalizedError {
    case missingSecret
    case http(Int)
    case notXtream
    case loginRefused
    case notAPlaylist
    case badAddress

    var errorDescription: String? {
        switch self {
        case .missingSecret: return L("The login data for this playlist is missing. Remove the playlist and add it again.")
        case .http(let code): return L("Server error %d.", code)
        case .notXtream: return L("The server did not answer like an Xtream server.")
        case .loginRefused: return L("The provider refused the login.")
        case .notAPlaylist: return L("The link does not contain a playlist.")
        case .badAddress: return L("Invalid address.")
        }
    }
}

/// Plain networking, not tied to any actor.
enum Net {
    static let userAgent = "VibeStream/1.5 (iOS)"

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 600
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return r
    }

    static func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: request(url))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ContentError.http(http.statusCode)
        }
        return data
    }
}

/// Loads categories, items, episodes and guide data of a playlist and keeps them in memory for the session.
@MainActor
final class ContentStore: ObservableObject {
    private var categoryCache: [String: [MediaCategory]] = [:]
    private var itemCache: [String: [MediaItem]] = [:]
    private var seriesCache: [String: SeriesDetail] = [:]
    private var m3uCache: [UUID: M3ULibrary.Library] = [:]

    private func key(_ playlist: UUID, _ kind: MediaKind, _ category: String?) -> String {
        "\(playlist.uuidString)|\(kind.rawValue)|\(category ?? "*")"
    }

    /// Forget everything loaded for [playlist] (reload button, playlist removed).
    func invalidate(_ playlist: UUID) {
        let prefix = playlist.uuidString + "|"
        categoryCache = categoryCache.filter { !$0.key.hasPrefix(prefix) }
        itemCache = itemCache.filter { !$0.key.hasPrefix(prefix) }
        seriesCache = seriesCache.filter { !$0.key.hasPrefix(prefix) }
        m3uCache[playlist] = nil
    }

    // MARK: - Login

    static func login(_ account: XtreamAccount) async throws -> Xtream.AuthInfo {
        guard let url = Xtream.apiURL(account) else { throw ContentError.badAddress }
        let data = try await Net.fetch(url)
        let info = Xtream.parseAuth(data)
        guard let ok = info.ok else { throw ContentError.notXtream }
        if !ok { throw ContentError.loginRefused }
        return info
    }

    // MARK: - Categories and items

    func categories(_ kind: MediaKind, in source: PlaylistSource) async throws -> [MediaCategory] {
        let k = key(source.playlist.id, kind, nil)
        if let cached = categoryCache[k] { return cached }
        let result: [MediaCategory]
        switch source {
        case .xtream(_, let account):
            guard let url = Xtream.apiURL(account, action: Xtream.action(forCategoriesOf: kind)) else { throw ContentError.badAddress }
            let data = try await Net.fetch(url)
            result = await Task.detached(priority: .userInitiated) { Xtream.parseCategories(data, kind: kind) }.value
        case .m3u(let playlist, let address):
            result = try await m3uLibrary(playlist, address: address).categories[kind] ?? []
        }
        categoryCache[k] = result
        return result
    }

    /// Items of one category, or of the whole playlist when [category] is nil.
    func items(_ kind: MediaKind, category: MediaCategory?, in source: PlaylistSource) async throws -> [MediaItem] {
        let playlistID = source.playlist.id
        let k = key(playlistID, kind, category?.id)
        if let cached = itemCache[k] { return cached }
        if let category = category, let all = itemCache[key(playlistID, kind, nil)] {
            return all.filter { $0.categoryID == category.id }
        }
        let result: [MediaItem]
        switch source {
        case .xtream(_, let account):
            var params: [(String, String)] = []
            if let category = category { params.append(("category_id", category.id)) }
            guard let url = Xtream.apiURL(account, action: Xtream.action(forItemsOf: kind), params: params) else { throw ContentError.badAddress }
            let data = try await Net.fetch(url)
            result = await Task.detached(priority: .userInitiated) {
                Xtream.parseItems(data, kind: kind, account: account, playlist: playlistID)
            }.value
        case .m3u(let playlist, let address):
            let all = try await m3uLibrary(playlist, address: address).items[kind] ?? []
            result = category.map { c in all.filter { $0.categoryID == c.id } } ?? all
        }
        itemCache[k] = result
        return result
    }

    // MARK: - Series

    func seriesDetail(for item: MediaItem, in source: PlaylistSource) async throws -> SeriesDetail {
        if let cached = seriesCache[item.id] { return cached }
        let result: SeriesDetail
        switch source {
        case .xtream(_, let account):
            guard let id = item.streamID,
                  let url = Xtream.apiURL(account, action: "get_series_info", params: [("series_id", id)]) else { throw ContentError.badAddress }
            let data = try await Net.fetch(url)
            result = await Task.detached(priority: .userInitiated) { Xtream.parseSeriesInfo(data, account: account) }.value
        case .m3u(let playlist, let address):
            let episodes = try await m3uLibrary(playlist, address: address).episodes[item.id] ?? []
            result = SeriesDetail(cover: item.logo, episodes: episodes)
        }
        seriesCache[item.id] = result
        return result
    }

    // MARK: - TV guide

    func guide(for item: MediaItem, in source: PlaylistSource) async throws -> [EPGEntry] {
        guard case .xtream(_, let account) = source, let id = item.streamID,
              let url = Xtream.apiURL(account, action: "get_short_epg", params: [("stream_id", id), ("limit", "12")]) else { return [] }
        let data = try await Net.fetch(url)
        let now = Date()
        return Xtream.parseEPG(data).filter { $0.end > now }
    }

    // MARK: - M3U

    private func m3uLibrary(_ playlist: Playlist, address: String) async throws -> M3ULibrary.Library {
        if let cached = m3uCache[playlist.id] { return cached }
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ContentError.badAddress
        }
        let playlistID = playlist.id
        let library = try await Task.detached(priority: .userInitiated) { () -> M3ULibrary.Library in
            // Read line by line: a playlist with 100,000 entries never has to be in memory as one text
            let (bytes, response) = try await Net.session.bytes(for: Net.request(url))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ContentError.http(http.statusCode)
            }
            var parser = M3UParser()
            var entries: [M3UEntry] = []
            for try await line in bytes.lines {
                if let entry = parser.feed(line) { entries.append(entry) }
            }
            if entries.isEmpty { throw ContentError.notAPlaylist }
            return M3ULibrary.build(entries, playlist: playlistID, epgURL: parser.epgURL)
        }.value
        m3uCache[playlist.id] = library
        return library
    }
}
