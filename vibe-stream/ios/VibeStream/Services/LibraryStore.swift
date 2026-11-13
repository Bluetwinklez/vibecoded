import Foundation
import VibeCore

/// Favorites, recently watched items and resume positions. Stored on the device only.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    struct Position: Codable, Hashable {
        var seconds: Double
        var duration: Double
        var updated: Date
    }

    @Published private(set) var favorites: [MediaItem] = []
    @Published private(set) var recents: [MediaItem] = []
    @Published private(set) var positions: [String: Position] = [:]

    private let defaults = UserDefaults.standard
    private static let favoritesKey = "vibe.library.favorites"
    private static let recentsKey = "vibe.library.recents"
    private static let positionsKey = "vibe.library.positions"
    private static let maxRecents = 40
    private static let maxPositions = 600

    private init() {
        favorites = load(Self.favoritesKey) ?? []
        recents = load(Self.recentsKey) ?? []
        positions = load(Self.positionsKey) ?? [:]
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func store<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    // MARK: - Favorites

    func isFavorite(_ item: MediaItem) -> Bool {
        favorites.contains { $0.id == item.id }
    }

    func toggleFavorite(_ item: MediaItem) {
        if let i = favorites.firstIndex(where: { $0.id == item.id }) {
            favorites.remove(at: i)
        } else {
            favorites.insert(item, at: 0)
        }
        store(favorites, Self.favoritesKey)
    }

    // MARK: - Recently watched

    func noteWatched(_ item: MediaItem) {
        recents.removeAll { $0.id == item.id }
        recents.insert(item, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
        store(recents, Self.recentsKey)
    }

    // MARK: - Resume positions

    func setPosition(_ key: String, seconds: Double, duration: Double) {
        guard seconds.isFinite, duration.isFinite, duration > 0 else { return }
        positions[key] = Position(seconds: seconds, duration: duration, updated: Date())
        if positions.count > Self.maxPositions {
            let oldest = positions.sorted { $0.value.updated < $1.value.updated }.prefix(positions.count - Self.maxPositions)
            for (k, _) in oldest { positions[k] = nil }
        }
        store(positions, Self.positionsKey)
    }

    /// Where to continue, or nil when the title was barely started or is (almost) finished.
    func resumePosition(_ key: String) -> Double? {
        guard let p = positions[key], p.seconds >= 60, p.seconds < p.duration * 0.95 else { return nil }
        return p.seconds
    }

    /// 0…1 for a progress bar, nil = never watched.
    func fraction(_ key: String) -> Double? {
        guard let p = positions[key], p.duration > 0 else { return nil }
        return min(1, max(0, p.seconds / p.duration))
    }

    func clearHistory() {
        recents = []
        positions = [:]
        store(recents, Self.recentsKey)
        store(positions, Self.positionsKey)
    }

    /// Drops everything that belongs to a removed playlist (item ids start with the playlist id).
    func removeAll(ofPlaylist id: UUID) {
        let prefix = id.uuidString + "|"
        favorites.removeAll { $0.id.hasPrefix(prefix) }
        recents.removeAll { $0.id.hasPrefix(prefix) }
        positions = positions.filter { !$0.key.hasPrefix(prefix) }
        store(favorites, Self.favoritesKey)
        store(recents, Self.recentsKey)
        store(positions, Self.positionsKey)
    }
}
