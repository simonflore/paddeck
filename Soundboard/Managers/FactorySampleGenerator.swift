import AVFoundation
import Foundation

/// Generates built-in synth samples as WAV files for use as factory presets.
enum FactorySampleGenerator {
    struct FactoryPreset {
        let name: String
        let filename: String
        let color: LaunchpadColor
        let generator: (Int, Double) -> Float  // (sampleIndex, sampleRate) -> amplitude
        let duration: Double
    }

    static let presets: [FactoryPreset] = [
        FactoryPreset(
            name: "Sine Tone",
            filename: "factory_sine.wav",
            color: LaunchpadColor(r: 10, g: 50, b: 127),   // Deep blue
            generator: { i, sr in
                let t = Double(i) / sr
                let env = envelope(t: t, duration: 2.0)
                return Float(sin(2.0 * .pi * 440.0 * t) * env)
            },
            duration: 2.0
        ),
        FactoryPreset(
            name: "Warm Pad",
            filename: "factory_pad.wav",
            color: LaunchpadColor(r: 90, g: 10, b: 127),   // Purple
            generator: { i, sr in
                let t = Double(i) / sr
                let env = envelope(t: t, duration: 3.0, attack: 0.3, release: 0.8)
                // Layer detuned sines for a lush pad
                let f = 220.0
                let s1 = sin(2.0 * .pi * f * t)
                let s2 = sin(2.0 * .pi * (f * 1.003) * t) * 0.8
                let s3 = sin(2.0 * .pi * (f * 2.0) * t) * 0.3
                let s4 = sin(2.0 * .pi * (f * 0.998) * t) * 0.7
                return Float((s1 + s2 + s3 + s4) * 0.3 * env)
            },
            duration: 3.0
        ),
        FactoryPreset(
            name: "Pluck",
            filename: "factory_pluck.wav",
            color: LaunchpadColor(r: 0, g: 110, b: 127),   // Cyan
            generator: { i, sr in
                let t = Double(i) / sr
                // Fast decay for plucky feel
                let env = exp(-t * 6.0)
                let f = 330.0
                let s1 = sin(2.0 * .pi * f * t)
                let s2 = sin(2.0 * .pi * f * 2.0 * t) * 0.5 * exp(-t * 10.0)
                let s3 = sin(2.0 * .pi * f * 3.0 * t) * 0.25 * exp(-t * 15.0)
                return Float((s1 + s2 + s3) * 0.5 * env)
            },
            duration: 1.5
        ),
        FactoryPreset(
            name: "Sub Bass",
            filename: "factory_bass.wav",
            color: LaunchpadColor(r: 127, g: 10, b: 10),   // Red
            generator: { i, sr in
                let t = Double(i) / sr
                let env = envelope(t: t, duration: 2.0, attack: 0.01, release: 0.4)
                let f = 55.0
                let s1 = sin(2.0 * .pi * f * t)
                // Subtle harmonic for presence
                let s2 = sin(2.0 * .pi * f * 2.0 * t) * 0.3
                return Float((s1 + s2) * 0.7 * env)
            },
            duration: 2.0
        ),
        FactoryPreset(
            name: "Bright Lead",
            filename: "factory_lead.wav",
            color: LaunchpadColor(r: 127, g: 127, b: 0),   // Yellow
            generator: { i, sr in
                let t = Double(i) / sr
                let env = envelope(t: t, duration: 2.0, attack: 0.01, release: 0.3)
                let f = 440.0
                // Sawtooth approximation (first 8 harmonics)
                var sample = 0.0
                for h in 1...8 {
                    sample += sin(2.0 * .pi * f * Double(h) * t) / Double(h)
                }
                return Float(sample * 0.25 * env)
            },
            duration: 2.0
        ),
        FactoryPreset(
            name: "Bell",
            filename: "factory_bell.wav",
            color: LaunchpadColor(r: 120, g: 120, b: 127), // Ice white
            generator: { i, sr in
                let t = Double(i) / sr
                // Inharmonic partials for metallic bell sound
                let f = 587.0
                let s1 = sin(2.0 * .pi * f * t) * exp(-t * 2.0)
                let s2 = sin(2.0 * .pi * f * 2.76 * t) * 0.6 * exp(-t * 4.0)
                let s3 = sin(2.0 * .pi * f * 5.4 * t) * 0.3 * exp(-t * 6.0)
                let s4 = sin(2.0 * .pi * f * 8.93 * t) * 0.15 * exp(-t * 8.0)
                return Float((s1 + s2 + s3 + s4) * 0.4)
            },
            duration: 3.0
        ),
    ]

    /// ADSR-style envelope.
    private static func envelope(
        t: Double,
        duration: Double,
        attack: Double = 0.01,
        release: Double = 0.3
    ) -> Double {
        let releaseStart = duration - release
        if t < attack {
            return t / attack
        } else if t < releaseStart {
            return 1.0
        } else if t < duration {
            return (duration - t) / release
        }
        return 0
    }

    /// Generate a WAV file for a preset and write it to the given directory.
    /// Returns the Sample if generation succeeded.
    static func generate(preset: FactoryPreset, in directory: URL) -> Sample? {
        let url = directory.appendingPathComponent(preset.filename)

        // Skip if already generated
        if FileManager.default.fileExists(atPath: url.path) {
            if let file = try? AVAudioFile(forReading: url) {
                let duration = Double(file.length) / file.fileFormat.sampleRate
                return Sample(name: preset.name, filename: preset.filename, fileDuration: duration)
            }
        }

        let sampleRate: Double = 44100
        let frameCount = AVAudioFrameCount(preset.duration * sampleRate)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount
        guard let data = buffer.floatChannelData?[0] else { return nil }

        for i in 0..<Int(frameCount) {
            data[i] = preset.generator(i, sampleRate)
        }

        // Write as 16-bit WAV
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        guard let file = try? AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        ) else { return nil }

        do {
            try file.write(from: buffer)
        } catch {
            return nil
        }

        return Sample(name: preset.name, filename: preset.filename, fileDuration: preset.duration)
    }

    /// Generate all factory samples that don't already exist.
    static func generateAll(in directory: URL) -> [Sample] {
        presets.compactMap { generate(preset: $0, in: directory) }
    }
}
