import Foundation
import VibeCore

/// A playlist together with its secret, ready for network requests.
enum PlaylistSource {
    case xtream(Playlist, XtreamAccount)
    case m3u(Playlist, String)

    var playlist: Playlist {
        switch self {
        case .xtream(let p, _): return p
        case .m3u(let p, _): return p
        }
    }
}

@MainActor
final class PlaylistRepository: ObservableObject {
    @Published private(set) var playlists: [Playlist] = []
    @Published var selectedID: UUID? {
        didSet { defaults.set(selectedID?.uuidString, forKey: Self.selectedKey) }
    }

    private static let listKey = "vibe.playlists"
    private static let selectedKey = "vibe.playlists.selected"
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: Self.listKey), let list = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = list
        }
        let saved = defaults.string(forKey: Self.selectedKey).flatMap { UUID(uuidString: $0) }
        selectedID = playlists.contains { $0.id == saved } ? saved : playlists.first?.id
    }

    var selected: Playlist? {
        playlists.first { $0.id == selectedID } ?? playlists.first
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) { defaults.set(data, forKey: Self.listKey) }
    }

    @discardableResult
    func addXtream(name: String, account: XtreamAccount) -> Playlist {
        let host = URLComponents(string: account.base)?.host ?? account.base
        let p = Playlist(name: name.isEmpty ? host : name, type: .xtream, server: account.base, username: account.username)
        Keychain.set(account.password, for: p.id.uuidString)
        playlists.append(p)
        selectedID = p.id
        save()
        return p
    }

    @discardableResult
    func addM3U(name: String, url: String) -> Playlist {
        let host = URLComponents(string: url)?.host ?? "M3U"
        let p = Playlist(name: name.isEmpty ? host : name, type: .m3u)
        Keychain.set(url, for: p.id.uuidString)
        playlists.append(p)
        selectedID = p.id
        save()
        return p
    }

    func remove(_ p: Playlist) {
        Keychain.delete(p.id.uuidString)
        playlists.removeAll { $0.id == p.id }
        if selectedID == p.id { selectedID = playlists.first?.id }
        save()
    }

    /// nil = the secret is missing from the Keychain (e.g. after restoring the phone from a backup).
    func source(for p: Playlist) -> PlaylistSource? {
        guard let secret = Keychain.get(p.id.uuidString), !secret.isEmpty else { return nil }
        switch p.type {
        case .xtream:
            return .xtream(p, XtreamAccount(base: p.server, username: p.username, password: secret))
        case .m3u:
            return .m3u(p, secret)
        }
    }

    var selectedSource: PlaylistSource? {
        selected.flatMap { source(for: $0) }
    }
}
