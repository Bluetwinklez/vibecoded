import SwiftUI
import VibeCore

/// Seasons and episodes of a series.
struct SeriesView: View {
    let item: MediaItem

    @EnvironmentObject private var playlists: PlaylistRepository
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerPresenter

    @State private var detail = SeriesDetail()
    @State private var phase: LoadPhase = .loading
    @State private var season = 1
    @State private var reloadToken = 0

    var body: some View {
        Group {
            switch phase {
            case .loading:
                LoadingView()
            case .failed(let message):
                MessageView(text: message) { reloadToken += 1 }
            case .loaded:
                if detail.episodes.isEmpty {
                    MessageView(text: L("No episodes found."))
                } else {
                    episodeList
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { library.toggleFavorite(item) } label: {
                    Image(systemName: library.isFavorite(item) ? "heart.fill" : "heart")
                }
            }
        }
        .task(id: reloadToken) { await load() }
    }

    private var episodeList: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    RemoteImage(url: detail.cover ?? item.logo, systemPlaceholder: "rectangle.stack")
                        .frame(width: 96, height: 144)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name).font(.headline)
                        if let genre = detail.genre { Text(genre).font(.caption).foregroundStyle(.secondary) }
                        if let plot = detail.plot { Text(plot).font(.footnote).foregroundStyle(.secondary).lineLimit(7) }
                    }
                }
                if detail.seasons.count > 1 {
                    Picker(L("Season %d", season), selection: $season) {
                        ForEach(detail.seasons, id: \.self) { s in
                            Text(L("Season %d", s)).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            Section {
                ForEach(detail.episodes(inSeason: season)) { episode in
                    Button { player.play(episode, of: item, following: following(episode)) } label: { EpisodeRow(episode: episode, series: item) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// All episodes after [episode] across seasons, in viewing order.
    private func following(_ episode: Episode) -> [Episode] {
        let all = detail.seasons.flatMap { detail.episodes(inSeason: $0) }
        guard let i = all.firstIndex(where: { $0.id == episode.id }) else { return [] }
        return Array(all[(i + 1)...])
    }

    private func load() async {
        guard let source = playlists.selectedSource else {
            phase = .failed(ContentError.missingSecret.localizedDescription)
            return
        }
        if detail.episodes.isEmpty { phase = .loading }
        do {
            let loaded = try await content.seriesDetail(for: item, in: source)
            detail = loaded
            if !loaded.seasons.contains(season) { season = loaded.seasons.first ?? 1 }
            phase = .loaded
        } catch {
            if isCancellation(error) { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let series: MediaItem
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        let key = PlayerPresenter.progressKey(episode, of: series)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(episode.number).").foregroundStyle(.secondary).monospacedDigit()
                Text(episode.title).lineLimit(2)
                Spacer(minLength: 8)
                Image(systemName: "play.fill").font(.caption).foregroundStyle(Theme.accent)
            }
            if let plot = episode.plot {
                Text(plot).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            if let fraction = library.fraction(key), fraction > 0.01 {
                ProgressView(value: fraction).tint(Theme.accent)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// What is on now and next on a channel (Xtream playlists).
struct GuideSheet: View {
    let item: MediaItem

    @EnvironmentObject private var playlists: PlaylistRepository
    @EnvironmentObject private var content: ContentStore
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [EPGEntry] = []
    @State private var phase: LoadPhase = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    LoadingView()
                case .failed(let message):
                    MessageView(text: message)
                case .loaded:
                    if entries.isEmpty {
                        MessageView(text: L("No guide data for this channel."))
                    } else {
                        List(entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(timeRange(entry)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    if entry.start <= Date(), entry.end > Date() {
                                        Text(L("Now")).font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                                    }
                                }
                                Text(entry.title).font(.body.weight(.medium))
                                if !entry.details.isEmpty {
                                    Text(entry.details).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("OK")) { dismiss() } }
            }
        }
        .task { await load() }
    }

    private func timeRange(_ e: EPGEntry) -> String {
        e.start.formatted(date: .omitted, time: .shortened) + " – " + e.end.formatted(date: .omitted, time: .shortened)
    }

    private func load() async {
        guard let source = playlists.selectedSource else {
            phase = .loaded
            return
        }
        do {
            entries = try await content.guide(for: item, in: source)
            phase = .loaded
        } catch {
            if isCancellation(error) { return }
            phase = .failed(error.localizedDescription)
        }
    }
}
