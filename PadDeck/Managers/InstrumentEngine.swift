import AVFoundation
import Foundation

@Observable
@MainActor
final class InstrumentEngine {
    private var samplers: [InstrumentType: AVAudioUnitSampler] = [:]
    private let audioEngine: AudioEngine

    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
    }

    /// Lazy-load the sampler for an instrument type. No-op if already loaded.
    func loadInstrument(_ type: InstrumentType) {
        guard samplers[type] == nil else { return }

        let sampler = AVAudioUnitSampler()
        audioEngine.avAudioEngine.attach(sampler)
        audioEngine.avAudioEngine.connect(sampler, to: audioEngine.mixerNode, format: nil)

        // Load SoundFont from app bundle
        if let url = Bundle.main.url(forResource: type.soundFontFilename, withExtension: "sf2") {
            let bankMSB: UInt8 = type == .drums ? UInt8(kAUSampler_DefaultPercussionBankMSB) : UInt8(kAUSampler_DefaultMelodicBankMSB)
            do {
                try sampler.loadSoundBankInstrument(at: url, program: 0, bankMSB: bankMSB, bankLSB: 0)
            } catch {
                print("[InstrumentEngine] Failed to load SoundFont for \(type.displayName): \(error)")
            }
        } else {
            print("[InstrumentEngine] SoundFont not found: \(type.soundFontFilename).sf2")
        }

        samplers[type] = sampler
    }

    func playNote(note: UInt8, velocity: UInt8, instrument: InstrumentType) {
        guard let sampler = samplers[instrument] else { return }
        let channel: UInt8 = instrument == .drums ? 9 : 0
        sampler.startNote(note, withVelocity: velocity, onChannel: channel)
    }

    func stopNote(note: UInt8, instrument: InstrumentType) {
        guard let sampler = samplers[instrument] else { return }
        let channel: UInt8 = instrument == .drums ? 9 : 0
        sampler.stopNote(note, onChannel: channel)
    }

    func stopAllNotes() {
        for (type, sampler) in samplers {
            let channel: UInt8 = type == .drums ? 9 : 0
            for note: UInt8 in 0...127 {
                sampler.stopNote(note, onChannel: channel)
            }
        }
    }

    func setVolume(_ volume: Float, for instrument: InstrumentType) {
        guard let sampler = samplers[instrument] else { return }
        // masterGain is in dB. Map 0-1 linear to dB.
        if volume <= 0 {
            sampler.masterGain = -90
        } else {
            sampler.masterGain = 20 * log10(volume)
        }
    }
}
