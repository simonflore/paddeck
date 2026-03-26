import Foundation

enum VocalActivationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case hold
    case select

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold: "Hold"
        case .select: "Select"
        }
    }

    var iconName: String {
        switch self {
        case .hold: "hand.tap.fill"
        case .select: "power"
        }
    }
}
