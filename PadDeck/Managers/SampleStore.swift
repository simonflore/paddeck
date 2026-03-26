import Foundation
import AVFoundation
import UniformTypeIdentifiers

@Observable
final class SampleStore {
    let audioDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        // Migrate legacy data directory
        let oldDir = appSupport.appendingPathComponent("Soundboard", isDirectory: true)
        let newDir = appSupport.appendingPathComponent("PadDeck", isDirectory: true)
        if FileManager.default.fileExists(atPath: oldDir.path) && !FileManager.default.fileExists(atPath: newDir.path) {
            try? FileManager.default.moveItem(at: oldDir, to: newDir)
        }

        self.audioDirectory = newDir
            .appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    }

    func importAudioFile(from sourceURL: URL) throws -> Sample {
        let filename = uniqueFilename(for: sourceURL.lastPathComponent)
        let destURL = audioDirectory.appendingPathComponent(filename)

        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let duration = try audioDuration(of: destURL)
        let name = sourceURL.deletingPathExtension().lastPathComponent

        return Sample(name: name, filename: filename, fileDuration: duration)
    }

    func audioFileURL(for sample: Sample) -> URL? {
        let url = audioDirectory.appendingPathComponent(sample.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func generateRecordingURL() -> URL {
        let filename = "Recording_\(dateFormatter.string(from: Date())).wav"
        return audioDirectory.appendingPathComponent(filename)
    }

    func sampleFromRecording(url: URL, name: String) throws -> Sample {
        let duration = try audioDuration(of: url)
        return Sample(name: name, filename: url.lastPathComponent, fileDuration: duration)
    }

    func deleteAudioFile(for sample: Sample) {
        guard let url = audioFileURL(for: sample) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Factory Samples

    /// Generate all factory samples (skips any already on disk). Call once at launch.
    func ensureFactorySamples() -> [Sample] {
        FactorySampleGenerator.generateAll(in: audioDirectory)
    }

    /// Check whether a filename belongs to a factory preset.
    func isFactorySample(_ sample: Sample) -> Bool {
        FactorySampleGenerator.presets.contains { $0.filename == sample.filename }
    }

    // MARK: - Private

    private func uniqueFilename(for original: String) -> String {
        var candidate = original
        var counter = 1
        while FileManager.default.fileExists(
            atPath: audioDirectory.appendingPathComponent(candidate).path
        ) {
            let ext = (original as NSString).pathExtension
            let base = (original as NSString).deletingPathExtension
            candidate = "\(base)_\(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    private func audioDuration(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.fileFormat.sampleRate
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()
}
