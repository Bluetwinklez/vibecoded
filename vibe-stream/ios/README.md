# Vibe Stream for iPhone and iPad

A native SwiftUI app. It shares no code with the Android app (an APK cannot run on iOS), but it reads the same
playlists: **Xtream Codes login** and **M3U links**.

## What it does

- Live TV, Movies, Series tabs with the provider's categories and search (case and accent insensitive)
- Series: seasons and episodes, resume position per episode
- Favorites, recently watched, resume for movies and episodes
- TV guide (now and next) for Xtream channels
- System player: picture-in-picture, AirPlay, audio and subtitle tracks, background audio
- Live TV reconnects by itself after short drops; Xtream live channels are played as HLS (`.m3u8`)
- Several playlists; login data in the iOS Keychain
- Texts in English, Turkish and German

## Limits (be aware before you rely on it)

- **Formats.** The iOS player plays HLS, MP4, MOV and M4V. It does **not** play MKV, AVI or raw MPEG-TS.
  Many IPTV movies are MKV. For those the app offers **Open in VLC** (free VLC app from the App Store).
- **No Stalker portals, no recording, no timeshift, no sports area, no phone remote** – those exist only on Android.
- **Not tested on a device yet.** The core logic (`VibeCore`) has unit tests that run with `swift test`;
  the app itself is built by CI (`.github/workflows/vibe-stream.yml`, job `ios`) but nobody has run it on an iPhone yet.

## Installing on an iPhone

Apple only installs apps that are signed. The CI build (`vibe-stream-unsigned-ipa` artifact) is **unsigned**, so it must
be signed on the way to the phone. Options:

| Way | Cost | Catch |
|---|---|---|
| **Sideloadly** or **AltStore** with your free Apple ID | free | app stops opening after **7 days** and must be re-signed (AltStore can do this automatically over Wi-Fi); max. 3 apps |
| Xcode on a Mac, your Apple ID, "Run" on the connected iPhone | free | same 7-day limit |
| Apple Developer Program | 99 USD / year | signed for 1 year, TestFlight possible |
| App Store | 99 USD / year | IPTV players without content are allowed, but review is strict; not prepared here |

Steps with Sideloadly (Windows or Mac): download the IPA from the Actions run, open Sideloadly, connect the iPhone,
drop the IPA in, sign in with your Apple ID, Start. On the iPhone: Settings > General > VPN & Device Management > trust
your Apple ID. Since iOS 16 also: Settings > Privacy & Security > Developer Mode > on.

## Building

```
brew install xcodegen
cd vibe-stream/ios
xcodegen generate
open VibeStream.xcodeproj
```

Core tests without Xcode (macOS or Linux): `swift test --package-path VibeCore`
