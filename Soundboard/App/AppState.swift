import Foundation
import SwiftUI

@Observable
final class AppState {
    var project: Project
    var selectedPad: GridPosition?
    var isRecordingPresented = false
    var showImportAlert = false
    var importAlertMessage = ""
    var mode: AppMode = .normal
    var isEditMode = false

    let midiManager: MIDIManager
    let audioEngine: AudioEngine
    let sampleStore: SampleStore
    let projectManager: ProjectManager
    let textScroller: TextScroller

    init() {
        let store = SampleStore()
        let projectMgr = ProjectManager(sampleStore: store)
        let midi = MIDIManager()
        self.sampleStore = store
        self.projectManager = projectMgr
        self.midiManager = midi
        self.audioEngine = AudioEngine(sampleStore: store)
        self.textScroller = TextScroller(midiManager: midi)
        self.project = projectMgr.loadLastProject() ?? Project(name: "Default")

        // Generate factory synth samples on first launch (no-op if already on disk)
        _ = store.ensureFactorySamples()

        // Preload loop buffers for instant playback
        for pad in project.pads where pad.playMode == .loop && pad.sample != nil {
            audioEngine.preloadLoopBuffer(for: pad)
        }
    }

    /// Logical side button index for XY mode toggle (0 = bottom right button).
    static let xyButtonIndex: Int = 0

    func setupMIDICallbacks() {
        midiManager.onPadPressed = { [weak self] position, velocity in
            self?.handlePadPress(position: position, velocity: velocity)
        }
        midiManager.onPadReleased = { [weak self] position in
            self?.handlePadRelease(position: position)
        }
        midiManager.onSideButtonPressed = { [weak self] index in
            guard let self else { return }
            if index == Self.xyButtonIndex {
                self.toggleXYMode()
            }
        }
        midiManager.onDeviceConnected = { [weak self] in
            guard let self else { return }
            self.midiManager.enterProgrammerMode()
            self.midiManager.syncLEDs(with: self.project, playingPads: self.audioEngine.activePads)
            self.updateXYButtonLED()
        }
        audioEngine.onPadStopped = { [weak self] position in
            guard let self else { return }
            // In XY mode, ignore pad stop callbacks (we manage playback manually)
            if case .xyPad = self.mode { return }
            self.textScroller.cancel()
            self.midiManager.syncLEDs(with: self.project, playingPads: self.audioEngine.activePads)
        }
    }

    func connectLaunchpad() {
        midiManager.scanForDevices()
    }

    func saveProject() {
        try? projectManager.save(project)
    }

    /// Update the Launchpad XY side button LED to reflect current state.
    func updateXYButtonLED() {
        if case .xyPad = mode {
            midiManager.setSideButtonLED(index: Self.xyButtonIndex, color: LaunchpadColor(r: 0, g: 40, b: 127))
        } else if canEnterXYMode {
            midiManager.setSideButtonLED(index: Self.xyButtonIndex, color: LaunchpadColor(r: 0, g: 10, b: 40))
        } else {
            midiManager.setSideButtonLED(index: Self.xyButtonIndex, color: .off)
        }
    }

    // MARK: - Pad Interaction

    func handlePadPress(position: GridPosition, velocity: UInt8) {
        // XY mode: route to XY handler
        if case .xyPad = mode {
            handleXYPress(position: position)
            return
        }

        let pad = project.pad(at: position)
        guard !pad.isEmpty else { return }

        // Audio first — minimize latency
        switch pad.playMode {
        case .oneShot:
            if audioEngine.isPlaying(at: position) {
                audioEngine.stop(at: position)
                midiManager.setLED(at: position, color: pad.color)
                selectedPad = position
                updateXYButtonLED()
                return
            } else {
                audioEngine.play(pad: pad, velocity: velocity)
            }
        case .oneShotStopOnRelease:
            audioEngine.play(pad: pad, velocity: velocity)
        case .loop:
            if audioEngine.isPlaying(at: position) {
                audioEngine.stop(at: position)
                midiManager.setLED(at: position, color: pad.color)
                selectedPad = position
                updateXYButtonLED()
                return
            } else {
                audioEngine.play(pad: pad, velocity: velocity)
            }
        }

        // LEDs and UI after audio is already playing
        selectedPad = position
        updateXYButtonLED()
        midiManager.setLED(at: position, color: .playing)

        if let name = pad.sample?.name {
            textScroller.textColor = LaunchpadColor(r: 127, g: 127, b: 127)
            textScroller.scrollText(
                name,
                project: project,
                activePads: { [weak self] in self?.audioEngine.activePads ?? [] }
            ) { [weak self] in
                guard let self else { return }
                self.midiManager.syncLEDs(with: self.project, playingPads: self.audioEngine.activePads)
            }
        }
    }

    func handlePadRelease(position: GridPosition) {
        // XY mode: stop sample on release
        if case .xyPad(let target, _) = mode {
            audioEngine.stop(at: target)
            audioEngine.resetEffects(at: target)
            mode = .xyPad(target: target, cursor: nil)
            midiManager.renderXYGrid(cursor: nil)
            return
        }

        let pad = project.pad(at: position)
        if pad.playMode == .oneShotStopOnRelease {
            audioEngine.stop(at: position)
        }
        if !audioEngine.isPlaying(at: position) {
            midiManager.setLED(at: position, color: pad.color)
        }
    }

    func updatePad(_ config: PadConfiguration, at position: GridPosition) {
        let oldSample = project.pad(at: position).sample
        project.setPad(config, at: position)
        midiManager.setLED(at: position, color: config.color)

        // Invalidate old sample cache if sample changed
        if let old = oldSample, old.id != config.sample?.id {
            audioEngine.invalidateFileCache(for: old.id.uuidString)
        }

        // Preload loop buffer for new config
        if config.playMode == .loop && config.sample != nil {
            audioEngine.preloadLoopBuffer(for: config)
        }

        saveProject()
    }

    func importFilesToFreePads(urls: [URL]) {
        let audioURLs = urls.filter { AudioFormats.isSupported($0) }
        guard !audioURLs.isEmpty else { return }

        let freePads = project.emptyPadsInVisualOrder()
        var importedCount = 0
        let pairsToImport = zip(audioURLs, freePads)

        for (url, position) in pairsToImport {
            guard let sample = try? sampleStore.importAudioFile(from: url) else { continue }
            var padConfig = project.pad(at: position)
            padConfig.sample = sample
            if padConfig.color == .off {
                padConfig.color = .defaultLoaded
            }
            project.setPad(padConfig, at: position)
            midiManager.setLED(at: position, color: padConfig.color)
            importedCount += 1
        }

        saveProject()

        let totalFiles = audioURLs.count
        let skippedCount = totalFiles - importedCount
        if skippedCount > 0 {
            importAlertMessage = "Imported \(importedCount) of \(totalFiles) files. \(skippedCount) skipped (not enough free pads)."
            showImportAlert = true
        }
    }

    func swapPads(_ a: GridPosition, _ b: GridPosition) {
        project.swapPads(a, b)
        midiManager.setLED(at: a, color: project.pad(at: a).color)
        midiManager.setLED(at: b, color: project.pad(at: b).color)
        saveProject()
    }

    // MARK: - XY Performance Pad

    /// Whether XY mode can be entered (selected pad has a sample loaded).
    var canEnterXYMode: Bool {
        guard let sel = selectedPad else { return false }
        return !project.pad(at: sel).isEmpty
    }

    func enterXYMode() {
        guard let target = selectedPad, !project.pad(at: target).isEmpty else { return }

        // Stop any normal playback on the target pad
        if audioEngine.isPlaying(at: target) {
            audioEngine.stop(at: target)
        }
        textScroller.cancel()
        mode = .xyPad(target: target, cursor: nil)
        midiManager.renderXYGrid(cursor: nil)
        updateXYButtonLED()
    }

    func exitXYMode() {
        if case .xyPad(let target, _) = mode {
            audioEngine.stop(at: target)
            audioEngine.resetEffects(at: target)
        }
        mode = .normal
        midiManager.syncLEDs(with: project, playingPads: audioEngine.activePads)
        updateXYButtonLED()
    }

    func toggleXYMode() {
        if case .xyPad = mode {
            exitXYMode()
        } else {
            enterXYMode()
        }
    }

    /// Pentatonic scale: semitones from root for each column (C major pentatonic, ~1.3 octaves).
    static let pentatonicSemitones: [Float] = [0, 2, 4, 7, 9, 12, 14, 16]
    /// Note names for HUD display.
    static let pentatonicNoteNames = ["C", "D", "E", "G", "A", "C'", "D'", "E'"]

    private func handleXYPress(position: GridPosition) {
        guard case .xyPad(let target, _) = mode else { return }

        let pad = project.pad(at: target)

        // X-axis: pentatonic pitch (snapped to scale degrees)
        let pitchCents = Self.pentatonicSemitones[position.column] * 100.0

        // Y-axis: volume (row 0 = soft 15%, row 7 = full 100%)
        let volume = 0.15 + (Float(position.row) / 7.0) * 0.85

        audioEngine.setPitch(at: target, cents: pitchCents)
        audioEngine.setVolume(at: target, volume: volume)

        // Play on first touch; slide without restarting
        if !audioEngine.isPlaying(at: target) {
            audioEngine.play(pad: pad, velocity: 127)
        }

        mode = .xyPad(target: target, cursor: position)
        midiManager.renderXYGrid(cursor: position)
    }
}
