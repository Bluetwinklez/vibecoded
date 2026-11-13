import AVFoundation
import SwiftUI

@main
struct VibeStreamApp: App {
    @StateObject private var playlists = PlaylistRepository()
    @StateObject private var content = ContentStore()
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = PlayerPresenter.shared

    init() {
        // Sound also with the mute switch on, and keep playing in picture-in-picture / in the background
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(playlists)
                .environmentObject(content)
                .environmentObject(library)
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
