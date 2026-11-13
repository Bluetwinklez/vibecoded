import SwiftUI
import VibeCore

struct RootView: View {
    @EnvironmentObject private var playlists: PlaylistRepository
    @EnvironmentObject private var player: PlayerPresenter

    var body: some View {
        Group {
            if playlists.playlists.isEmpty {
                NavigationStack { AddPlaylistView(showsCancel: false) }
            } else {
                TabView {
                    BrowseView(kind: .live)
                        .tabItem { Label(L("Live TV"), systemImage: "tv") }
                    BrowseView(kind: .movie)
                        .tabItem { Label(L("Movies"), systemImage: "film") }
                    BrowseView(kind: .series)
                        .tabItem { Label(L("Series"), systemImage: "rectangle.stack") }
                    MyListView()
                        .tabItem { Label(L("My list"), systemImage: "heart") }
                    SettingsView()
                        .tabItem { Label(L("Settings"), systemImage: "gearshape") }
                }
            }
        }
        .alert(L("Playback failed"), isPresented: failureShown, presenting: player.failure) { failure in
            Button(L("Open in VLC")) { player.openInVLC(failure.originalURL) }
            Button(L("OK"), role: .cancel) {}
        } message: { _ in
            Text(L("The stream could not be played. The provider may be offline, the connection limit may be reached, or the format is not supported by iOS."))
        }
        .confirmationDialog(L("Format not supported"), isPresented: unsupportedShown, titleVisibility: .visible, presenting: player.unsupported) { info in
            Button(L("Open in VLC")) { player.openInVLC(info.request.originalURL) }
            Button(L("Try anyway")) { player.start(info.request) }
            Button(L("Cancel"), role: .cancel) {}
        } message: { info in
            Text(L("The built-in iOS player cannot open %@ files. The free VLC app can.", info.format))
        }
    }

    private var failureShown: Binding<Bool> {
        Binding(get: { player.failure != nil }, set: { if !$0 { player.failure = nil } })
    }

    private var unsupportedShown: Binding<Bool> {
        Binding(get: { player.unsupported != nil }, set: { if !$0 { player.unsupported = nil } })
    }
}
