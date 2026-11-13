import SwiftUI
import VibeCore

/// Recently watched items and favorites of the selected playlist.
struct MyListView: View {
    @EnvironmentObject private var playlists: PlaylistRepository
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerPresenter

    private func mine(_ items: [MediaItem]) -> [MediaItem] {
        guard let id = playlists.selected?.id else { return [] }
        let prefix = id.uuidString + "|"
        return items.filter { $0.id.hasPrefix(prefix) }
    }

    var body: some View {
        let recents = mine(library.recents)
        let favorites = mine(library.favorites)
        NavigationStack {
            Group {
                if recents.isEmpty && favorites.isEmpty {
                    MessageView(text: L("Nothing here yet."))
                } else {
                    List {
                        if !recents.isEmpty {
                            Section(L("Continue watching")) {
                                ForEach(recents.prefix(15)) { item in row(item) }
                            }
                        }
                        if !favorites.isEmpty {
                            Section(L("Favorites")) {
                                ForEach(favorites) { item in
                                    row(item).swipeActions { FavoriteButton(item: item).tint(.red) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("My list"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { PlaylistMenu() }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: MediaItem) -> some View {
        if item.kind == .series {
            NavigationLink { SeriesView(item: item) } label: { label(item) }
        } else {
            Button { player.play(item) } label: { label(item) }
                .buttonStyle(.plain)
        }
    }

    private func label(_ item: MediaItem) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: item.logo, systemPlaceholder: item.kind == .live ? "tv" : "film")
                .frame(width: 52, height: item.kind == .live ? 36 : 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).lineLimit(2)
                if let fraction = library.fraction(item.id), fraction > 0.01 {
                    ProgressView(value: fraction).tint(Theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
