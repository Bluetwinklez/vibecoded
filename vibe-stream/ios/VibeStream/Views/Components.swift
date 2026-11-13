import SwiftUI
import VibeCore

/// Channel logo or poster from the network, with a neutral placeholder while loading or when missing.
struct RemoteImage: View {
    let url: String?
    var systemPlaceholder = "photo"

    var body: some View {
        if let s = url, let u = URL(string: s) {
            AsyncImage(url: u) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    placeholder
                default:
                    Theme.surface
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.surface
            Image(systemName: systemPlaceholder).foregroundStyle(.secondary)
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L("Loading…")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MessageView: View {
    let text: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let retry = retry {
                Button(L("Try again"), action: retry).buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Row of a live channel.
struct ChannelRow: View {
    let item: MediaItem
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: item.logo, systemPlaceholder: "tv")
                .frame(width: 52, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(item.name).lineLimit(2)
            Spacer(minLength: 8)
            if library.isFavorite(item) {
                Image(systemName: "heart.fill").foregroundStyle(Theme.accent).font(.footnote)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Poster card of a movie or a series.
struct PosterCard: View {
    let item: MediaItem
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: item.logo, systemPlaceholder: item.kind == .series ? "rectangle.stack" : "film")
                    .frame(maxWidth: .infinity)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        if let rating = item.rating {
                            Text(String(format: "%.1f", rating))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.65), in: Capsule())
                                .padding(6)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if library.isFavorite(item) {
                            Image(systemName: "heart.fill").foregroundStyle(Theme.accent).font(.caption).padding(8)
                        }
                    }
                if let fraction = library.fraction(item.id), fraction > 0.01 {
                    ProgressView(value: fraction).tint(Theme.accent).padding(.horizontal, 6).padding(.bottom, 6)
                }
            }
            Text(item.name)
                .font(.footnote)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Favorite toggle for context menus and swipe actions.
struct FavoriteButton: View {
    let item: MediaItem
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        let isFavorite = library.isFavorite(item)
        Button {
            library.toggleFavorite(item)
        } label: {
            Label(L(isFavorite ? "Remove from favorites" : "Add to favorites"), systemImage: isFavorite ? "heart.slash" : "heart")
        }
    }
}

/// Shows items the right way for their kind: channels as a list, movies and series as a poster grid.
struct ItemCollection: View {
    let items: [MediaItem]
    @EnvironmentObject private var player: PlayerPresenter
    @State private var guideItem: MediaItem?

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 170), spacing: 12)]

    var body: some View {
        Group {
            if items.first?.kind == .live {
                List(items) { item in
                    Button { player.play(item) } label: { ChannelRow(item: item) }
                        .buttonStyle(.plain)
                        .swipeActions { FavoriteButton(item: item).tint(Theme.violet) }
                        .contextMenu {
                            FavoriteButton(item: item)
                            if item.streamID != nil {
                                Button { guideItem = item } label: { Label(L("TV guide"), systemImage: "list.bullet.rectangle") }
                            }
                        }
                }
                .listStyle(.plain)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { item in
                            cell(item).contextMenu { FavoriteButton(item: item) }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .sheet(item: $guideItem) { item in GuideSheet(item: item) }
    }

    @ViewBuilder
    private func cell(_ item: MediaItem) -> some View {
        if item.kind == .series {
            NavigationLink { SeriesView(item: item) } label: { PosterCard(item: item) }
                .buttonStyle(.plain)
        } else {
            Button { player.play(item) } label: { PosterCard(item: item) }
                .buttonStyle(.plain)
        }
    }
}
