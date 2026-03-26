import Foundation

struct VocalPadConfig: Codable, Equatable, Sendable {
    var effect: VocalEffect
    var activationMode: VocalActivationMode
    var dryWetMix: Float

    init(
        effect: VocalEffect = .reverb,
        activationMode: VocalActivationMode = .hold,
        dryWetMix: Float = 0.5
    ) {
        self.effect = effect
        self.activationMode = activationMode
        self.dryWetMix = dryWetMix
    }
}
