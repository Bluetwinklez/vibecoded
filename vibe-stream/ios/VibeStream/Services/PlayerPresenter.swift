import AVFoundation
import AVKit
import SwiftUI
import UIKit
import VibeCore

/// What to play: the addresses are tried in order (e.g. the HLS form of a live channel first).
struct PlayRequest {
    var title: String
    var urls: [URL]
    /// Address as the playlist gave it; used to hand the stream to VLC when iOS cannot play it.
    var originalURL: String
    /// Key for the resume position; nil for live TV.
    var progressKey: String?
    var isLive: Bool
    var startAt: Double?
}

struct PlaybackFailure: Identifiable {
    let id = UUID()
    var title: String
    var originalURL: String
}

struct UnsupportedFormat: Identifiable {
    let id = UUID()
    var request: PlayRequest
    var format: String
}

/// Presents the system player (AVPlayerViewController: picture-in-picture, AirPlay, subtitles and audio tracks
/// come for free) and looks after fallback addresses, live reconnects and resume positions.
@MainActor
final class PlayerPresenter: NSObject, ObservableObject, AVPlayerViewControllerDelegate {
    static let shared = PlayerPresenter()

    @Published var failure: PlaybackFailure?
    @Published var unsupported: UnsupportedFormat?

    private var player: AVPlayer?
    private var controller: AVPlayerViewController?
    private var request: PlayRequest?
    private var urlIndex = 0
    private var liveRetries = 0
    private var didSeekToStart = false
    private var wasOnScreen = false
    private var pipActive = false
    private var statusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var failObserver: NSObjectProtocol?
    private var watchdog: Timer?

    private static let maxLiveRetries = 5

    // MARK: - Entry points

    func play(_ item: MediaItem) {
        guard let url = item.url else { return }
        LibraryStore.shared.noteWatched(item)
        let key = item.kind == .live ? nil : item.id
        open(title: item.name, url: url, kind: item.kind, progressKey: key)
    }

    func play(_ episode: Episode, of series: MediaItem) {
        LibraryStore.shared.noteWatched(series)
        let title = "\(series.name) · S\(episode.season) E\(episode.number)"
        open(title: title, url: episode.url, kind: .series, progressKey: Self.progressKey(episode, of: series))
    }

    static func progressKey(_ episode: Episode, of series: MediaItem) -> String {
        "\(series.id)|\(episode.id)"
    }

    private func open(title: String, url: String, kind: MediaKind, progressKey: String?) {
        let candidates = Playback.candidates(for: url, kind: kind).compactMap { URL(string: $0) }
        let startAt = progressKey.flatMap { LibraryStore.shared.resumePosition($0) }
        var req = PlayRequest(title: title, urls: candidates, originalURL: url, progressKey: progressKey,
                              isLive: kind == .live, startAt: startAt)
        if candidates.isEmpty {
            // mkv, avi, raw MPEG-TS …: AVPlayer cannot open these. Ask instead of failing silently.
            if let direct = URL(string: url) { req.urls = [direct] }
            unsupported = UnsupportedFormat(request: req, format: (Playback.fileExtension(of: url) ?? "?").uppercased())
            return
        }
        start(req)
    }

    func start(_ req: PlayRequest) {
        guard !req.urls.isEmpty else {
            failure = PlaybackFailure(title: req.title, originalURL: req.originalURL)
            return
        }
        tearDown(dismiss: true)
        request = req
        urlIndex = 0
        liveRetries = 0
        didSeekToStart = false
        wasOnScreen = false

        let player = AVPlayer()
        player.allowsExternalPlayback = true
        let vc = AVPlayerViewController()
        vc.player = player
        vc.delegate = self
        vc.allowsPictureInPicturePlayback = true
        vc.modalPresentationStyle = .fullScreen
        vc.title = req.title
        self.player = player
        self.controller = vc

        if !req.isLive, req.progressKey != nil {
            let interval = CMTime(seconds: 5, preferredTimescale: 1)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                Task { @MainActor in self?.savePosition(time) }
            }
        }
        loadCurrentURL()
        Self.topController()?.present(vc, animated: true)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDismissed() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    // MARK: - Loading and fallbacks

    private func loadCurrentURL() {
        guard let req = request, let player = player, urlIndex < req.urls.count else {
            giveUp()
            return
        }
        let item = AVPlayerItem(url: req.urls[urlIndex])
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor in self?.statusChanged(of: observed) }
        }
        if let old = failObserver { NotificationCenter.default.removeObserver(old) }
        failObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.playbackBroke() }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func statusChanged(of item: AVPlayerItem) {
        guard item === player?.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            liveRetries = 0
            if !didSeekToStart, let start = request?.startAt {
                didSeekToStart = true
                player?.seek(to: CMTime(seconds: start, preferredTimescale: 600))
            }
        case .failed:
            // This address does not work: try the next one, then give up
            urlIndex += 1
            loadCurrentURL()
        default:
            break
        }
    }

    /// A stream that was already running stopped (provider hiccup, network change). Live TV reconnects a few times.
    private func playbackBroke() {
        guard let req = request, req.isLive, liveRetries < Self.maxLiveRetries else {
            if request?.isLive == true { giveUp() }
            return
        }
        liveRetries += 1
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self = self, self.request != nil else { return }
            self.loadCurrentURL()
        }
    }

    private func giveUp() {
        let req = request
        tearDown(dismiss: true)
        if let req = req { failure = PlaybackFailure(title: req.title, originalURL: req.originalURL) }
    }

    // MARK: - Resume position

    private func savePosition(_ time: CMTime) {
        guard let key = request?.progressKey, let item = player?.currentItem else { return }
        let duration = item.duration.seconds
        let seconds = time.seconds
        guard seconds.isFinite, duration.isFinite, duration > 0 else { return }
        LibraryStore.shared.setPosition(key, seconds: seconds, duration: duration)
    }

    // MARK: - Lifetime

    /// The system player has no "was closed" callback, so a timer watches whether it is still on screen.
    private func checkDismissed() {
        guard let vc = controller else { return }
        let onScreen = vc.viewIfLoaded?.window != nil
        if onScreen { wasOnScreen = true }
        if wasOnScreen, !onScreen, !pipActive, !vc.isBeingPresented, !vc.isBeingDismissed {
            tearDown(dismiss: false)
        }
    }

    private func tearDown(dismiss: Bool) {
        watchdog?.invalidate()
        watchdog = nil
        if let player = player, let item = player.currentItem { savePosition(item.currentTime()) }
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
        timeObserver = nil
        statusObservation = nil
        if let old = failObserver { NotificationCenter.default.removeObserver(old) }
        failObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        if dismiss, let vc = controller, vc.presentingViewController != nil { vc.dismiss(animated: false) }
        controller?.player = nil
        controller = nil
        player = nil
        request = nil
        pipActive = false
    }

    // MARK: - Picture in picture

    nonisolated func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        Task { @MainActor in self.pipActive = true }
    }

    nonisolated func playerViewController(_ playerViewController: AVPlayerViewController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in self.pipActive = false }
    }

    nonisolated func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        Task { @MainActor in self.pipActive = false }
    }

    nonisolated func playerViewController(_ playerViewController: AVPlayerViewController,
                                          restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            guard playerViewController.presentingViewController == nil, let top = Self.topController() else {
                completionHandler(true)
                return
            }
            top.present(playerViewController, animated: true) { completionHandler(true) }
        }
    }

    // MARK: - External player

    static let vlcStoreURL = URL(string: "https://apps.apple.com/app/vlc-media-player/id650377962")!

    /// Opens the stream in VLC, or the App Store page of VLC when it is not installed.
    func openInVLC(_ url: String) {
        guard let vlc = Playback.vlcURL(for: url) else { return }
        if UIApplication.shared.canOpenURL(vlc) {
            UIApplication.shared.open(vlc)
        } else {
            UIApplication.shared.open(Self.vlcStoreURL)
        }
    }

    // MARK: - Helpers

    static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}
