import Foundation

enum PlayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case oneShot
    case oneShotStopOnRelease
    case loop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oneShot: "One Shot"
        case .oneShotStopOnRelease: "Hold to Play"
        case .loop: "Loop"
        }
    }

    var iconName: String {
        switch self {
        case .oneShot: "play.fill"
        case .oneShotStopOnRelease: "hand.tap.fill"
        case .loop: "repeat"
        }
    }
}
