import SwiftUI

struct LaunchpadColor: Codable, Hashable, Sendable {
    var r: UInt8  // 0-127
    var g: UInt8  // 0-127
    var b: UInt8  // 0-127

    var swiftUIColor: Color {
        Color(
            red: Double(r) / 127.0,
            green: Double(g) / 127.0,
            blue: Double(b) / 127.0
        )
    }

    static let off = LaunchpadColor(r: 0, g: 0, b: 0)
    static let defaultLoaded = LaunchpadColor(r: 10, g: 50, b: 127)
    static let playing = LaunchpadColor(r: 0, g: 127, b: 0)
    static let recording = LaunchpadColor(r: 127, g: 0, b: 0)
    static let vocal = LaunchpadColor(r: 127, g: 0, b: 80)

    // Vibrant sport-event presets — punchy, saturated, arena-ready
    static let presets: [LaunchpadColor] = [
        LaunchpadColor(r: 127, g: 10, b: 10),     // Hot Red
        LaunchpadColor(r: 127, g: 70, b: 0),      // Electric Orange
        LaunchpadColor(r: 127, g: 127, b: 0),     // Stadium Yellow
        LaunchpadColor(r: 80, g: 127, b: 0),      // Lime Green
        LaunchpadColor(r: 20, g: 127, b: 20),     // Turf Green
        LaunchpadColor(r: 0, g: 127, b: 60),      // Emerald
        LaunchpadColor(r: 0, g: 127, b: 127),     // Teal
        LaunchpadColor(r: 0, g: 110, b: 127),     // Aqua Cyan
        LaunchpadColor(r: 10, g: 50, b: 127),     // Deep Blue
        LaunchpadColor(r: 60, g: 20, b: 127),     // Indigo
        LaunchpadColor(r: 90, g: 10, b: 127),     // Neon Purple
        LaunchpadColor(r: 127, g: 0, b: 127),     // Magenta
        LaunchpadColor(r: 127, g: 10, b: 90),     // Hot Pink
        LaunchpadColor(r: 127, g: 30, b: 50),     // Rose
        LaunchpadColor(r: 127, g: 80, b: 40),     // Amber
        LaunchpadColor(r: 90, g: 60, b: 30),      // Bronze
        LaunchpadColor(r: 127, g: 100, b: 80),    // Peach
        LaunchpadColor(r: 80, g: 127, b: 100),    // Mint
        LaunchpadColor(r: 120, g: 120, b: 127),   // Ice White
        LaunchpadColor(r: 50, g: 50, b: 55),      // Slate Gray
    ]
}
