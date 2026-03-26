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

    var isMicActive = false
    var micGain: Float {
        get { UserDefaults.standard.float(forKey: "micGain") }
        set {
            UserDefaults.standard.set(newValue, forKey: "micGain")
            audioEngine.setMicGain(newValue)
        }
    }

    var vocalPadPosition: GridPosition? {
        project.pads.first(where: { $0.isVocalPad })?.position
    }

    let midiManager: MIDIManager
    let audioEngine: AudioEngine
    let sampleStore: SampleStore
    let projectManager: ProjectManager
    let textScroller: TextScroller

    init() {
        UserDefaults.standard.register(defaults: ["micGain": Float(1.0)])
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

        audioEngine.setMicGain(micGain)
    }

    func setupMIDICallbacks() {
        midiManager.onPadPressed = { [weak self] position, velocity in
            self?.handlePadPress(position: position, velocity: velocity)
        }
        midiManager.onPadReleased = { [weak self] position in
            self?.handlePadRelease(position: position)
        }
        midiManager.onSideButtonPressed = { [weak self] index in
            guard let self, self.vocalPadPosition != nil else { return }
            self.handleDryWetButton(index: index)
        }
        midiManager.onDeviceConnected = { [weak self] in
            guard let self else { return }
            self.midiManager.enterProgrammerMode()
            self.midiManager.syncLEDs(with: self.project, playingPads: self.audioEngine.activePads)
            self.renderDryWetMeter()
        }
        audioEngine.onPadStopped = { [weak self] position in
            guard let self else { return }
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

    // MARK: - Pad Interaction

    func handlePadPress(position: GridPosition, velocity: UInt8) {
        let pad = project.pad(at: position)

        // Vocal pad: gate mic instead of playing a sample
        if pad.isVocalPad, let vocalConfig = pad.vocalConfig {
            selectedPad = position
            switch vocalConfig.activationMode {
            case .hold:
                audioEngine.setMicActive(true)
                isMicActive = true
            case .select:
                isMicActive.toggle()
                audioEngine.setMicActive(isMicActive)
            }
            // LED feedback
            if isMicActive {
                midiManager.setLEDPulsing(at: position, colorIndex: 53)
            } else {
                midiManager.setLED(at: position, color: pad.color)
            }
            return
        }

        guard !pad.isEmpty else { return }

        // Audio first — minimize latency
        switch pad.playMode {
        case .oneShot:
            if audioEngine.isPlaying(at: position) {
                audioEngine.stop(at: position)
                midiManager.setLED(at: position, color: pad.color)
                selectedPad = position
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
                return
            } else {
                audioEngine.play(pad: pad, velocity: velocity)
            }
        }

        // LEDs and UI after audio is already playing
        selectedPad = position
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
        let pad = project.pad(at: position)

        // Vocal pad hold mode: deactivate mic on release
        if pad.isVocalPad && pad.vocalConfig?.activationMode == .hold {
            audioEngine.setMicActive(false)
            isMicActive = false
            midiManager.setLED(at: position, color: pad.color)
            return
        }

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

        // Sync vocal effect settings
        if config.isVocalPad, let vocal = config.vocalConfig {
            audioEngine.switchVocalEffect(to: vocal.effect)
            audioEngine.setVocalDryWet(vocal.dryWetMix)
        }

        // Turn off mic if vocal pad was removed
        if !config.isVocalPad && isMicActive && vocalPadPosition == nil {
            deactivateMic()
        }

        renderDryWetMeter()

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

    func deactivateMic() {
        audioEngine.setMicActive(false)
        isMicActive = false
        if let pos = vocalPadPosition {
            midiManager.setLED(at: pos, color: project.pad(at: pos).color)
        }
    }

    // MARK: - Dry/Wet Scene Buttons

    /// Current dry/wet step (0–6), mapped from the vocal pad's dryWetMix.
    private var dryWetStep: Int {
        guard let pos = vocalPadPosition,
              let config = project.pad(at: pos).vocalConfig else { return 3 }
        return Int(round(config.dryWetMix * 6.0))
    }

    private func handleDryWetButton(index: Int) {
        guard let pos = vocalPadPosition else { return }
        var pad = project.pad(at: pos)
        guard var config = pad.vocalConfig else { return }

        var step = dryWetStep
        if index == 7 { // Up
            step = min(6, step + 1)
        } else if index == 6 { // Down
            step = max(0, step - 1)
        } else {
            return // meter LEDs, not interactive
        }

        config.dryWetMix = Float(step) / 6.0
        pad.vocalConfig = config
        updatePad(pad, at: pos)
        audioEngine.setVocalDryWet(config.dryWetMix)
        renderDryWetMeter()
    }

    func renderDryWetMeter() {
        guard vocalPadPosition != nil else {
            // No vocal pad — turn off all scene buttons
            for i in 0..<8 {
                midiManager.setSideButtonLED(index: i, color: .off)
            }
            return
        }

        let step = dryWetStep

        // Bar meter colors: gradient from green (dry) to blue (wet)
        let meterColors: [LaunchpadColor] = [
            LaunchpadColor(r: 0, g: 127, b: 20),
            LaunchpadColor(r: 0, g: 100, b: 60),
            LaunchpadColor(r: 0, g: 80, b: 90),
            LaunchpadColor(r: 0, g: 60, b: 110),
            LaunchpadColor(r: 0, g: 40, b: 127),
            LaunchpadColor(r: 0, g: 20, b: 127),
        ]
        let dimColor = LaunchpadColor(r: 8, g: 8, b: 8)

        for i in 0..<6 {
            let color = i < step ? meterColors[i] : dimColor
            midiManager.setSideButtonLED(index: i, color: color)
        }

        // Up/down buttons: white
        let controlColor = LaunchpadColor(r: 60, g: 60, b: 60)
        midiManager.setSideButtonLED(index: 6, color: controlColor)
        midiManager.setSideButtonLED(index: 7, color: controlColor)
    }
}
