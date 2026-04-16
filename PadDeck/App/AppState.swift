import Foundation
import SwiftUI

struct ActiveInstrument: Sendable {
    let type: InstrumentType
    let sourcePosition: GridPosition
}

@Observable
@MainActor
final class AppState {
    var project: Project
    var selectedPad: GridPosition?
    var isRecordingPresented = false
    /// Incremented each time the Launchpad record button is pressed to signal RecordView.
    var recordToggleCount = 0
    /// Pad held down when recording starts — auto-saves recording to this pad on stop.
    var recordTargetPad: GridPosition?
    /// Pads currently physically held on the Launchpad (for hold+record workflow).
    var heldPads: Set<GridPosition> = []
    var showImportAlert = false
    var importAlertMessage = ""
    var isEditMode = false
    var activeInstrument: ActiveInstrument?
    var sideButtonIndicator: SideButtonIndicator?
    private var indicatorDismissWork: DispatchWorkItem?

    // Bundle import state
    var pendingImport: PadDeckBundle.ImportPreview?
    var showBundleImportAlert = false
    var bundleImportError: String?
    var showBundleImportError = false
    var saveError: String?
    var showSaveError = false

    var isMicActive = false
    private(set) var vocalPadPosition: GridPosition?
    var micGain: Float {
        get { UserDefaults.standard.float(forKey: "micGain") }
        set {
            UserDefaults.standard.set(newValue, forKey: "micGain")
            audioEngine.setMicGain(newValue)
        }
    }

    var duckExternalAudio: Bool {
        get { UserDefaults.standard.bool(forKey: "duckExternalAudio") }
        set {
            UserDefaults.standard.set(newValue, forKey: "duckExternalAudio")
            audioEngine.duckingEnabled = newValue
        }
    }

    let midiManager: MIDIManager
    let audioEngine: AudioEngine
    let sampleStore: SampleStore
    let projectManager: ProjectManager
    let textScroller: TextScroller
    let instrumentEngine: InstrumentEngine

    init() {
        UserDefaults.standard.register(defaults: ["micGain": Float(1.0), "duckExternalAudio": true])
        let store = SampleStore()
        let projectMgr = ProjectManager(sampleStore: store)
        let midi = MIDIManager()
        self.sampleStore = store
        self.projectManager = projectMgr
        self.midiManager = midi
        self.audioEngine = AudioEngine(sampleStore: store)
        self.textScroller = TextScroller(midiManager: midi)
        self.instrumentEngine = InstrumentEngine(audioEngine: self.audioEngine)
        self.project = projectMgr.loadLastProject() ?? Project(name: "Default")

        // Generate factory synth samples on first launch (no-op if already on disk)
        _ = store.ensureFactorySamples()

        // Preload loop buffers for instant playback
        for pad in project.pads where pad.playMode == .loop && pad.sample != nil {
            audioEngine.preloadLoopBuffer(for: pad)
        }

        audioEngine.setMicGain(micGain)
        audioEngine.duckingEnabled = duckExternalAudio
        vocalPadPosition = project.pads.first(where: { $0.isVocalPad })?.position
    }

    func setupMIDICallbacks() {
        midiManager.onPadPressed = { [weak self] position, velocity in
            self?.handlePadPress(position: position, velocity: velocity)
        }
        midiManager.onPadReleased = { [weak self] position in
            self?.handlePadRelease(position: position)
        }
        midiManager.onSideButtonPressed = { [weak self] _ in
            // Side buttons are display-only (dry/wet meter) — no interaction
            guard self != nil else { return }
        }
        midiManager.onTopButtonPressed = { [weak self] index in
            self?.handleTopButton(index: index)
        }
        midiManager.onDeviceConnected = { [weak self] in
            guard let self else { return }
            self.midiManager.enterProgrammerMode()
            if let active = self.activeInstrument {
                self.renderInstrumentGrid(active.type)
            } else {
                self.midiManager.syncLEDs(with: self.project, playingPads: self.audioEngine.activePads)
                self.renderDryWetMeter()
                self.renderTopButtonLEDs()
            }
        }
        audioEngine.onPadStopped = { [weak self] position in
            guard let self else { return }
            #if DEBUG
            if self.activeInstrument != nil {
                print("[Instrument] WARNING: onPadStopped fired during instrument mode for \(position) — syncLEDs will overwrite grid")
            }
            #endif
            self.textScroller.cancel()
            if self.activeInstrument != nil {
                // Don't overwrite instrument grid when a leftover sample finishes
                return
            }
            self.midiManager.syncLEDs(with: self.project, playingPads: self.audioEngine.activePads)
        }
    }

    func connectLaunchpad() {
        midiManager.scanForDevices()
    }

    func saveProject() {
        do {
            try projectManager.save(project)
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
        }
    }

    private func refreshVocalPadPosition() {
        vocalPadPosition = project.pads.first(where: { $0.isVocalPad })?.position
    }

    func switchProject(_ newProject: Project) {
        if activeInstrument != nil {
            exitInstrumentMode()
        }
        deactivateMic()
        audioEngine.stopAll()
        audioEngine.invalidateAllCaches()
        project = newProject
        selectedPad = nil
        refreshVocalPadPosition()
        midiManager.syncLEDs(with: project, playingPads: audioEngine.activePads)
        renderDryWetMeter()
    }

    // MARK: - Pad Interaction

    func handlePadPress(position: GridPosition, velocity: UInt8) {
        heldPads.insert(position)
        if isEditMode { selectedPad = position }
        // Instrument mode: route all pads to note playback
        if let active = activeInstrument {
            let layout = active.type.noteLayout
            guard let note = layout.noteForPosition(position) else { return }
            instrumentEngine.playNote(note: note, velocity: velocity, instrument: active.type)
            midiManager.setLED(at: position, color: layout.pressedColor)
            return
        }

        let pad = project.pad(at: position)

        // Instrument pad: enter instrument mode (requires Launchpad, not during edit mode)
        if pad.isInstrumentPad, let config = pad.instrumentConfig, !isEditMode, midiManager.isConnected {
            activeInstrument = ActiveInstrument(type: config.instrumentType, sourcePosition: position)
            instrumentEngine.loadInstrument(config.instrumentType)
            instrumentEngine.setVolume(config.volume, for: config.instrumentType)
            renderInstrumentGrid(config.instrumentType)
            return
        }

        // Vocal pad: gate mic instead of playing a sample
        if pad.isVocalPad, let vocalConfig = pad.vocalConfig {
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
                return
            } else {
                audioEngine.play(pad: pad, velocity: velocity)
            }
        }

        // LEDs after audio is already playing
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
        heldPads.remove(position)
        // Instrument mode: send note-off
        if let active = activeInstrument {
            let layout = active.type.noteLayout
            guard let note = layout.noteForPosition(position) else { return }
            instrumentEngine.stopNote(note: note, instrument: active.type)
            midiManager.setLED(at: position, color: layout.colorForPosition(position))
            return
        }

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
        refreshVocalPadPosition()
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

    // MARK: - Instrument Mode

    func exitInstrumentMode() {
        instrumentEngine.stopAllNotes()
        activeInstrument = nil
        midiManager.syncLEDs(with: project, playingPads: audioEngine.activePads)
        // Turn off top-row LEDs
        for i in 0..<8 {
            midiManager.setTopButtonLED(index: i, color: .off)
        }
        renderDryWetMeter()
    }

    func renderInstrumentGrid(_ type: InstrumentType) {
        let layout = type.noteLayout
        var entries: [(position: GridPosition, color: LaunchpadColor)] = []
        for row in 0..<8 {
            for col in 0..<8 {
                let pos = GridPosition(row: row, column: col)
                entries.append((position: pos, color: layout.colorForPosition(pos)))
            }
        }
        midiManager.sendBatchLEDs(entries)

        // Exit button: light both top-right (CC 98) and side-top (note 89) red
        let exitColor = LaunchpadColor(r: 127, g: 20, b: 20)
        for i in 0..<7 {
            midiManager.setSideButtonLED(index: i, color: .off)
            midiManager.setTopButtonLED(index: i, color: .off)
        }
        midiManager.setSideButtonLED(index: 7, color: exitColor)
        midiManager.setTopButtonLED(index: 7, color: exitColor)
    }

    // MARK: - Bundle Import

    func handleOpenURL(_ url: URL) {
        do {
            let preview = try PadDeckBundle.previewImport(from: url, projectManager: projectManager)
            pendingImport = preview
            if preview.existingProject != nil {
                showBundleImportAlert = true
            } else {
                finalizeBundleImport(mode: .createNew)
            }
        } catch {
            bundleImportError = error.localizedDescription
            showBundleImportError = true
        }
    }

    func finalizeBundleImport(mode: PadDeckBundle.ImportMode) {
        guard let preview = pendingImport else { return }
        do {
            let imported = try PadDeckBundle.finalizeImport(
                preview: preview,
                mode: mode,
                sampleStore: sampleStore,
                projectManager: projectManager
            )
            switchProject(imported)
            pendingImport = nil
        } catch {
            bundleImportError = error.localizedDescription
            showBundleImportError = true
            pendingImport = nil
        }
    }

    // MARK: - Top Button Handler

    func handleTopButton(index: Int) {
        // Instrument mode: top-right button exits, all others swallowed
        if activeInstrument != nil {
            if index == 7 {
                showSideButtonIndicator(SideButtonIndicator(
                    message: "Exit Instrument Mode",
                    icon: "xmark.circle.fill",
                    accentColor: .red
                ))
                exitInstrumentMode()
                renderTopButtonLEDs()
            }
            return
        }
        switch index {
        case 2: // Left arrow — dry/wet down
            handleDryWetButton(direction: .down)
        case 3: // Right arrow — dry/wet up
            handleDryWetButton(direction: .up)
        case 4: // Play/Edit toggle
            isEditMode.toggle()
            showSideButtonIndicator(SideButtonIndicator(
                message: isEditMode ? "Edit Mode" : "Play Mode",
                icon: isEditMode ? "pencil" : "play.fill",
                accentColor: isEditMode ? .orange : .green
            ))
            renderTopButtonLEDs()
        case 5: // Mic toggle
            guard vocalPadPosition != nil else { break }
            isMicActive.toggle()
            audioEngine.setMicActive(isMicActive)
            if let pos = vocalPadPosition {
                if isMicActive {
                    midiManager.setLEDPulsing(at: pos, colorIndex: 53)
                } else {
                    midiManager.setLED(at: pos, color: project.pad(at: pos).color)
                }
            }
            showSideButtonIndicator(SideButtonIndicator(
                message: isMicActive ? "Mic On" : "Mic Off",
                icon: isMicActive ? "mic.fill" : "mic.slash",
                accentColor: isMicActive ? .pink : .gray
            ))
            renderTopButtonLEDs()
        case 6: // Stop All
            showSideButtonIndicator(SideButtonIndicator(
                message: "Stop All",
                icon: "stop.fill",
                accentColor: .red
            ))
            deactivateMic()
            audioEngine.stopAll()
            midiManager.syncLEDs(with: project, playingPads: audioEngine.activePads)
            renderDryWetMeter()
            renderTopButtonLEDs()
        case 7: // Record — toggle start/stop recording
            if audioEngine.isRecording {
                showSideButtonIndicator(SideButtonIndicator(
                    message: "Stop Recording",
                    icon: "stop.circle",
                    accentColor: .red
                ))
            } else {
                // Check if an empty pad is held — target it for auto-save
                let emptyHeld = heldPads.first { project.pad(at: $0).isEmpty }
                recordTargetPad = emptyHeld
                showSideButtonIndicator(SideButtonIndicator(
                    message: "Record",
                    icon: "record.circle",
                    accentColor: .red
                ))
            }
            recordToggleCount += 1
            if !isRecordingPresented {
                isRecordingPresented = true
            }
        default:
            break
        }
    }

    func renderTopButtonLEDs() {
        // 0-1: unused (dim)
        midiManager.setTopButtonLED(index: 0, color: .off)
        midiManager.setTopButtonLED(index: 1, color: .off)

        // 2-3: Dry/Wet arrows — blue when vocal pad exists
        let dryWetColor = vocalPadPosition != nil
            ? LaunchpadColor(r: 20, g: 60, b: 127)
            : LaunchpadColor.off
        midiManager.setTopButtonLED(index: 2, color: dryWetColor)
        midiManager.setTopButtonLED(index: 3, color: dryWetColor)

        // 4: Play/Edit — green (play) or orange (edit)
        let modeColor = isEditMode
            ? LaunchpadColor(r: 127, g: 80, b: 0)
            : LaunchpadColor(r: 0, g: 127, b: 0)
        midiManager.setTopButtonLED(index: 4, color: modeColor)

        // 5: Mic — pink when active, dim otherwise
        let micColor = isMicActive && vocalPadPosition != nil
            ? LaunchpadColor(r: 127, g: 20, b: 80)
            : (vocalPadPosition != nil ? LaunchpadColor(r: 40, g: 8, b: 25) : .off)
        midiManager.setTopButtonLED(index: 5, color: micColor)

        // 6: Stop All — always red
        midiManager.setTopButtonLED(index: 6, color: LaunchpadColor(r: 127, g: 0, b: 0))

        // 7: Record — always red
        midiManager.setTopButtonLED(index: 7, color: LaunchpadColor(r: 127, g: 0, b: 0))
    }

    // MARK: - Dry/Wet Scene Buttons

    // MARK: - Side Button Indicator

    private func showSideButtonIndicator(_ indicator: SideButtonIndicator, duration: Double = 1.8) {
        withAnimation { sideButtonIndicator = indicator }
        indicatorDismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation { self?.sideButtonIndicator = nil }
        }
        indicatorDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private enum DryWetDirection { case up, down }

    /// Current dry/wet step (0–8), mapped from the vocal pad's dryWetMix.
    var dryWetStep: Int {
        guard let pos = vocalPadPosition,
              let config = project.pad(at: pos).vocalConfig else { return 4 }
        return Int(round(config.dryWetMix * 8.0))
    }

    private var dryWetSaveWork: DispatchWorkItem?

    private func handleDryWetButton(direction: DryWetDirection) {
        guard let pos = vocalPadPosition else { return }
        var pad = project.pad(at: pos)
        guard var config = pad.vocalConfig else { return }

        var step = dryWetStep
        switch direction {
        case .up:   step = min(8, step + 1)
        case .down: step = max(0, step - 1)
        }

        config.dryWetMix = Float(step) / 8.0
        pad.vocalConfig = config
        project.setPad(pad, at: pos)
        audioEngine.setVocalDryWet(config.dryWetMix)
        renderDryWetMeter()

        let percentage = Int(round(config.dryWetMix * 100))
        showSideButtonIndicator(SideButtonIndicator(
            message: "Dry/Wet: \(percentage)%",
            icon: "slider.horizontal.3",
            accentColor: Color(red: 0.2, green: 0.6, blue: 1.0)
        ))

        // Debounce save — rapid button presses only persist once settled
        dryWetSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveProject() }
        dryWetSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
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

        // Bar meter colors: gradient from green (dry) to blue (wet) — 8 levels
        let meterColors: [LaunchpadColor] = [
            LaunchpadColor(r: 0, g: 127, b: 10),
            LaunchpadColor(r: 0, g: 110, b: 40),
            LaunchpadColor(r: 0, g: 95, b: 65),
            LaunchpadColor(r: 0, g: 80, b: 90),
            LaunchpadColor(r: 0, g: 60, b: 110),
            LaunchpadColor(r: 0, g: 45, b: 120),
            LaunchpadColor(r: 0, g: 30, b: 127),
            LaunchpadColor(r: 0, g: 15, b: 127),
        ]
        let dimColor = LaunchpadColor(r: 8, g: 8, b: 8)

        for i in 0..<8 {
            let color = i < step ? meterColors[i] : dimColor
            midiManager.setSideButtonLED(index: i, color: color)
        }
    }
}
