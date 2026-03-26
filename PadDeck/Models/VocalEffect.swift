import Foundation

enum VocalEffect: String, Codable, CaseIterable, Identifiable, Sendable {
    case reverb
    case delay
    case pitchShift
    case distortion

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reverb: "Reverb"
        case .delay: "Delay"
        case .pitchShift: "Pitch Shift"
        case .distortion: "Distortion"
        }
    }

    var iconName: String {
        switch self {
        case .reverb: "waveform.path"
        case .delay: "repeat.1"
        case .pitchShift: "arrow.up.arrow.down"
        case .distortion: "bolt.fill"
        }
    }
}
