// swift-tools-version:5.9
import PackageDescription

// Pure logic of the iOS app (no UIKit/SwiftUI): playlist parsing, Xtream API, playback rules, search.
// Kept in its own package so it can be unit-tested with `swift test` on a Mac without a simulator.
let package = Package(
    name: "VibeCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "VibeCore", targets: ["VibeCore"])
    ],
    targets: [
        .target(name: "VibeCore"),
        .testTarget(name: "VibeCoreTests", dependencies: ["VibeCore"])
    ]
)
