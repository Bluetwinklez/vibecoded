import SwiftUI
import VibeCore

/// One tab (Live TV, Movies or Series): categories of the selected playlist, with search over the whole tab.
struct BrowseView: View {
    let kind: MediaKind

    @EnvironmentObject private var playlists: PlaylistRepository
    @EnvironmentObject private var content: ContentStore

    @State private var categories: [MediaCategory] = []
    @State private var phase: LoadPhase = .loading
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var searching = false
    @State private var reloadToken = 0

    private var title: String {
        switch kind {
        case .live: return L("Live TV")
        case .movie: return L("Movies")
        case .series: return L("Series")
        }
    }

    private var loadKey: String {
        "\(playlists.selected?.id.uuidString ?? "-")#\(reloadToken)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchResults
                } else {
                    switch phase {
                    case .loading:
                        LoadingView()
                    case .failed(let message):
                        MessageView(text: message) { reloadToken += 1 }
                    case .loaded:
                        categoryList
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { PlaylistMenu() }
            }
            .searchable(text: $query, prompt: L("Search"))
        }
        .task(id: loadKey) { await load() }
        .task(id: query) { await search() }
    }

    private var categoryList: some View {
        List {
            NavigationLink {
                ItemsView(kind: kind, category: nil, title: L("All"))
            } label: {
                Label(L("All"), systemImage: "square.grid.2x2")
            }
            Section(L("Categories")) {
                ForEach(categories) { category in
                    NavigationLink(category.name) {
                        ItemsView(kind: kind, category: category, title: category.name)
                    }
                }
            }
        }
        .refreshable {
            if let id = playlists.selected?.id { content.invalidate(id) }
            await load()
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if searching {
            LoadingView()
        } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
            MessageView(text: L("Type at least 2 characters."))
        } else if results.isEmpty {
            MessageView(text: L("No results."))
        } else {
            ItemCollection(items: results)
        }
    }

    private func load() async {
        guard let playlist = playlists.selected else { return }
        guard let source = playlists.source(for: playlist) else {
            phase = .failed(ContentError.missingSecret.localizedDescription)
            return
        }
        phase = .loading
        do {
            categories = try await content.categories(kind, in: source)
            phase = .loaded
        } catch {
            if isCancellation(error) { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, let source = playlists.selectedSource else {
            results = []
            searching = false
            return
        }
        // Wait a moment so that not every typed letter starts a search
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        searching = results.isEmpty
        do {
            let all = try await content.items(kind, category: nil, in: source)
            if Task.isCancelled { return }
            results = await Task.detached(priority: .userInitiated) { Search.filter(all, query: text) }.value
        } catch {
            results = []
        }
        searching = false
    }
}

/// Switches between the saved playlists.
struct PlaylistMenu: View {
    @EnvironmentObject private var playlists: PlaylistRepository

    var body: some View {
        if playlists.playlists.count > 1 {
            Menu {
                ForEach(playlists.playlists) { p in
                    Button {
                        playlists.selectedID = p.id
                    } label: {
                        if p.id == playlists.selected?.id {
                            Label(p.name, systemImage: "checkmark")
                        } else {
                            Text(p.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
            }
        }
    }
}

/// The items of one category (or of the whole tab).
struct ItemsView: View {
    let kind: MediaKind
    let category: MediaCategory?
    let title: String

    @EnvironmentObject private var playlists: PlaylistRepository
    @EnvironmentObject private var content: ContentStore

    @State private var items: [MediaItem] = []
    @State private var phase: LoadPhase = .loading
    @State private var reloadToken = 0

    var body: some View {
        Group {
            switch phase {
            case .loading:
                LoadingView()
            case .failed(let message):
                MessageView(text: message) { reloadToken += 1 }
            case .loaded:
                if items.isEmpty {
                    MessageView(text: L("Nothing here yet."))
                } else {
                    ItemCollection(items: items)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadToken) { await load() }
    }

    private func load() async {
        guard let source = playlists.selectedSource else {
            phase = .failed(ContentError.missingSecret.localizedDescription)
            return
        }
        if items.isEmpty { phase = .loading }
        do {
            items = try await content.items(kind, category: category, in: source)
            phase = .loaded
        } catch {
            if isCancellation(error) { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

/// A load that was cancelled because its screen went away or reloaded is not an error to show.
func isCancellation(_ error: Error) -> Bool {
    Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
}
