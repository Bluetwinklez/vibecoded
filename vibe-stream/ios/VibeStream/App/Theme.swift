import SwiftUI

enum Theme {
    static let background = Color(red: 14 / 255, green: 11 / 255, blue: 31 / 255)
    static let surface = Color(red: 28 / 255, green: 24 / 255, blue: 52 / 255)
    static let accent = Color(red: 255 / 255, green: 64 / 255, blue: 129 / 255)
    static let violet = Color(red: 124 / 255, green: 77 / 255, blue: 255 / 255)
    static let amber = Color(red: 255 / 255, green: 171 / 255, blue: 64 / 255)
    static let gradient = LinearGradient(colors: [violet, accent, amber], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// State of a screen that loads its content from the network.
enum LoadPhase: Equatable {
    case loading
    case loaded
    case failed(String)
}
