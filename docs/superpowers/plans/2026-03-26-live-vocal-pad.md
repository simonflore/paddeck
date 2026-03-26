# Live Vocal Pad Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a live microphone-through-pad feature with selectable vocal effects and Launchpad dry/wet control.

**Architecture:** Pre-attach 4 AVAudioUnit effect nodes to the engine at startup. Route `engine.inputNode → micGainNode → [activeEffect] → mixer`. Hot-swap connections between effects without engine pause. Gate mic via `micGainNode.volume`. Scene buttons (right column) control dry/wet as a 6-LED bar meter.

**Tech Stack:** AVAudioEngine, AVAudioUnitReverb/Delay/TimePitch/Distortion, CoreMIDI, SwiftUI

**Spec:** `docs/superpowers/specs/2026-03-26-live-vocal-pad-design.md`

---

### Task 1: Add New Model Types

**Files:**
- Create: `Soundboard/Models/VocalEffect.swift`
- Create: `Soundboard/Models/VocalActivationMode.swift`
- Create: `Soundboard/Models/VocalPadConfig.swift`

- [ ] **Step 1: Create VocalEffect enum**

```swift
// Soundboard/Models/VocalEffect.swift
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
```

- [ ] **Step 2: Create VocalActivationMode enum**

```swift
// Soundboard/Models/VocalActivationMode.swift
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
```

- [ ] **Step 3: Create VocalPadConfig struct**

```swift
// Soundboard/Models/VocalPadConfig.swift
import Foundation

struct VocalPadConfig: Codable, Sendable {
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
```

- [ ] **Step 4: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodegen generate && xcodebuild -scheme Soundboard -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Soundboard/Models/VocalEffect.swift Soundboard/Models/VocalActivationMode.swift Soundboard/Models/VocalPadConfig.swift
git commit -m "feat: add VocalEffect, VocalActivationMode, and VocalPadConfig model types"
```

---

### Task 2: Update PadConfiguration and Project

**Files:**
- Modify: `Soundboard/Models/PadConfiguration.swift`
- Modify: `Soundboard/Models/Project.swift`

- [ ] **Step 1: Add vocalConfig to PadConfiguration**

In `Soundboard/Models/PadConfiguration.swift`, add the `vocalConfig` property, update `isEmpty`, and add `isVocalPad`. Update both initializers to accept `vocalConfig`:

```swift
struct PadConfiguration: Codable, Identifiable, Sendable {
    let position: GridPosition
    var sample: Sample?
    var color: LaunchpadColor
    var playMode: PlayMode
    var volume: Float
    var emoji: String?
    var vocalConfig: VocalPadConfig?

    var id: Int { position.id }
    var isEmpty: Bool { sample == nil && vocalConfig == nil }
    var isVocalPad: Bool { vocalConfig != nil }

    init(position: GridPosition) {
        self.position = position
        self.sample = nil
        self.color = .off
        self.playMode = .oneShot
        self.volume = 1.0
        self.emoji = nil
        self.vocalConfig = nil
    }

    init(position: GridPosition, sample: Sample?, color: LaunchpadColor, playMode: PlayMode, volume: Float, emoji: String? = nil, vocalConfig: VocalPadConfig? = nil) {
        self.position = position
        self.sample = sample
        self.color = color
        self.playMode = playMode
        self.volume = volume
        self.emoji = emoji
        self.vocalConfig = vocalConfig
    }
}
```

- [ ] **Step 2: Update Project.swapPads to include vocalConfig**

In `Soundboard/Models/Project.swift`, update the `swapPads` method at line 61 to pass `vocalConfig`:

```swift
    mutating func swapPads(_ a: GridPosition, _ b: GridPosition) {
        guard a != b else { return }
        let padA = pads[a.id]
        let padB = pads[b.id]
        pads[a.id] = PadConfiguration(position: a, sample: padB.sample, color: padB.color, playMode: padB.playMode, volume: padB.volume, emoji: padB.emoji, vocalConfig: padB.vocalConfig)
        pads[b.id] = PadConfiguration(position: b, sample: padA.sample, color: padA.color, playMode: padA.playMode, volume: padA.volume, emoji: padA.emoji, vocalConfig: padA.vocalConfig)
        modifiedAt = Date()
    }
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodegen generate && xcodebuild -scheme Soundboard -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Soundboard/Models/PadConfiguration.swift Soundboard/Models/Project.swift
git commit -m "feat: add vocalConfig to PadConfiguration, update swapPads"
```

---

### Task 3: Remove XY Mode

**Files:**
- Modify: `Soundboard/Models/AppMode.swift`
- Modify: `Soundboard/App/AppState.swift`
- Modify: `Soundboard/Managers/AudioEngine.swift`
- Modify: `Soundboard/Views/Grid/GridView.swift`
- Modify: `Soundboard/Views/Grid/ContentView.swift`
- Modify: `Soundboard/Views/Grid/PadView.swift`

- [ ] **Step 1: Simplify AppMode**

Replace the entire contents of `Soundboard/Models/AppMode.swift` with:

```swift
import Foundation

enum AppMode: Equatable {
    case normal
}
```

- [ ] **Step 2: Remove XY mode from AppState**

In `Soundboard/App/AppState.swift`:

1. Remove `static let xyButtonIndex: Int = 0` (line 41)

2. Remove the XY toggle in `setupMIDICallbacks()` — replace the `onSideButtonPressed` closure (lines 50-55) with an empty handler for now:

```swift
        midiManager.onSideButtonPressed = { [weak self] index in
            _ = self // placeholder — vocal pad scene buttons added in Task 5
        }
```

3. Remove `updateXYButtonLED()` method (lines 80-88)

4. In `onDeviceConnected` closure (lines 56-61), remove the `self.updateXYButtonLED()` call (line 60)

5. In `onPadStopped` closure (lines 62-68), remove the XY guard (lines 64-65: `if case .xyPad = self.mode { return }`)

6. In `handlePadPress` (lines 92-144):
   - Remove lines 93-97 (XY mode guard)
   - Remove `updateXYButtonLED()` calls on lines 109, 121, 130

7. In `handlePadRelease` (lines 146-163):
   - Remove lines 147-154 (XY mode release handling)

8. Remove `updateXYButtonLED()` method entirely (lines 79-88)
9. Remove `canEnterXYMode` computed property (lines 222-226)
10. Remove `enterXYMode()` method (lines 228-239)
11. Remove `exitXYMode()` method (lines 241-249)
12. Remove `toggleXYMode()` method (lines 251-257)
13. Remove `pentatonicSemitones` and `pentatonicNoteNames` statics (lines 259-262)
14. Remove `handleXYPress()` method (lines 264-285)

- [ ] **Step 3: Remove XY-only methods from AudioEngine**

In `Soundboard/Managers/AudioEngine.swift`, remove these methods that were only used by XY mode:

- `setPitch(at:cents:)` (lines 111-113)
- `setRate(at:rate:)` (lines 116-118)
- `setVolume(at:volume:)` (lines 121-123)
- `resetEffects(at:)` (lines 126-129)
- `resetAllEffects()` (lines 131-136)

- [ ] **Step 4: Remove XY overlay from GridView**

In `Soundboard/Views/Grid/GridView.swift`, remove the entire `.overlay` block that renders the XY HUD (lines 23-61):

```swift
        .overlay {
            if case .xyPad(_, let cursor) = appState.mode {
                // ... entire XY overlay
            }
        }
```

Remove it entirely (the block from `.overlay {` at line 23 through the closing `}` at line 61).

- [ ] **Step 5: Remove XY button and references from ContentView**

In `Soundboard/Views/Grid/ContentView.swift`:

1. Remove the `isXYMode` computed property (lines 6-9)
2. Remove the `canEnterXY` computed property (lines 11-13)
3. Remove the entire "XY Performance Pad toggle" Button block (lines 69-98)
4. In the "Stop All" button action (lines 101-104), remove line 102: `if case .xyPad = appState.mode { appState.exitXYMode() }`

- [ ] **Step 6: Remove updateXYButtonLED() call from PadView**

In `Soundboard/Views/Grid/PadView.swift`, line 127: remove `appState.updateXYButtonLED()`.

- [ ] **Step 7: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodegen generate && xcodebuild -scheme Soundboard -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add Soundboard/Models/AppMode.swift Soundboard/App/AppState.swift Soundboard/Managers/AudioEngine.swift Soundboard/Views/Grid/GridView.swift Soundboard/Views/Grid/ContentView.swift Soundboard/Views/Grid/PadView.swift
git commit -m "refactor: remove XY performance pad mode entirely"
```

---

### Task 4: Add Mic Chain to AudioEngine

**Files:**
- Modify: `Soundboard/Managers/AudioEngine.swift`

- [ ] **Step 1: Add mic chain properties**

Add these properties to the `AudioEngine` class, after the existing property declarations (after line 16):

```swift
    // Vocal mic chain
    private let micGainNode = AVAudioMixerNode()
    private let reverbNode = AVAudioUnitReverb()
    private let delayNode = AVAudioUnitDelay()
    private let vocalPitchNode = AVAudioUnitTimePitch()
    private let distortionNode = AVAudioUnitDistortion()
    private var activeVocalEffect: VocalEffect = .reverb
    var globalMicGain: Float = 1.0
```

- [ ] **Step 2: Add setupMicChain() method**

Add this private method, called from `setupEngine()`:

```swift
    private func setupMicChain() {
        // Configure effect defaults
        reverbNode.loadFactoryPreset(.largeHall2)
        reverbNode.wetDryMix = 50

        delayNode.delayTime = 0.3
        delayNode.feedback = 30
        delayNode.lowPassCutoff = 15000
        delayNode.wetDryMix = 50

        vocalPitchNode.pitch = 1200 // +1 octave
        vocalPitchNode.wetDryMix = 50

        distortionNode.loadFactoryPreset(.speechWaves)
        distortionNode.wetDryMix = 50

        // Attach all nodes (but only connect the active effect)
        engine.attach(micGainNode)
        engine.attach(reverbNode)
        engine.attach(delayNode)
        engine.attach(vocalPitchNode)
        engine.attach(distortionNode)

        micGainNode.volume = 0 // Start muted

        // Connect: inputNode → micGainNode → reverbNode (default) → mixer
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        engine.connect(engine.inputNode, to: micGainNode, format: inputFormat)
        engine.connect(micGainNode, to: reverbNode, format: nil)
        engine.connect(reverbNode, to: mixer, format: nil)

        activeVocalEffect = .reverb
    }
```

- [ ] **Step 3: Call setupMicChain() from setupEngine()**

In the existing `setupEngine()` method, add the call after attaching the mixer but before starting the engine:

```swift
    private func setupEngine() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        setupMicChain()
        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            print("AudioEngine failed to start: \(error)")
        }
    }
```

- [ ] **Step 4: Add mic control methods**

Add these public methods to AudioEngine:

```swift
    // MARK: - Vocal Mic

    func setMicActive(_ active: Bool) {
        micGainNode.volume = active ? globalMicGain : 0
    }

    func switchVocalEffect(to effect: VocalEffect) {
        guard effect != activeVocalEffect else { return }

        let oldNode = effectNode(for: activeVocalEffect)
        let newNode = effectNode(for: effect)

        // Disconnect old: micGainNode → oldNode → mixer
        engine.disconnectNodeOutput(micGainNode)
        engine.disconnectNodeOutput(oldNode)

        // Connect new: micGainNode → newNode → mixer
        engine.connect(micGainNode, to: newNode, format: nil)
        engine.connect(newNode, to: mixer, format: nil)

        activeVocalEffect = effect
    }

    func setVocalDryWet(_ value: Float) {
        let node = effectNode(for: activeVocalEffect)
        if let reverb = node as? AVAudioUnitReverb {
            reverb.wetDryMix = value * 100
        } else if let delay = node as? AVAudioUnitDelay {
            delay.wetDryMix = value * 100
        } else if let pitch = node as? AVAudioUnitTimePitch {
            pitch.wetDryMix = value * 100
        } else if let dist = node as? AVAudioUnitDistortion {
            dist.wetDryMix = value * 100
        }
    }

    func setMicGain(_ gain: Float) {
        globalMicGain = gain
        // Update live volume if mic is currently unmuted
        if micGainNode.volume > 0 {
            micGainNode.volume = gain
        }
    }

    private func effectNode(for effect: VocalEffect) -> AVAudioNode {
        switch effect {
        case .reverb: reverbNode
        case .delay: delayNode
        case .pitchShift: vocalPitchNode
        case .distortion: distortionNode
        }
    }
```

- [ ] **Step 5: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodegen generate && xcodebuild -scheme Soundboard -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Soundboard/Managers/AudioEngine.swift
git commit -m "feat: add mic chain with pre-attached vocal effect nodes"
```

---

### Task 5: Add Vocal Pad Logic to AppState

**Files:**
- Modify: `Soundboard/App/AppState.swift`

- [ ] **Step 1: Add vocal pad properties**

Add these properties to AppState, after the existing property declarations:

```swift
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
```

Register the default so `float(forKey:)` returns 1.0 when unset but allows 0.0 when explicitly set. In `init()`, before any other code:

```swift
        UserDefaults.standard.register(defaults: ["micGain": Float(1.0)])
```

- [ ] **Step 2: Initialize mic gain on startup**

At the end of `init()`, after the loop preload, add:

```swift
        audioEngine.setMicGain(micGain)
```

- [ ] **Step 3: Add vocal pad handling to handlePadPress**

In `handlePadPress(position:velocity:)`, after getting `pad` and before the `guard !pad.isEmpty` check, add vocal pad handling:

```swift
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
                midiManager.setLEDPulsing(at: position, colorIndex: 53) // magenta pulse
            } else {
                midiManager.setLED(at: position, color: pad.color)
            }
            return
        }

        guard !pad.isEmpty else { return }

        // ... existing sample playback logic unchanged ...
```

- [ ] **Step 4: Add vocal pad handling to handlePadRelease**

In `handlePadRelease(position:)`, add vocal pad handling at the top:

```swift
    func handlePadRelease(position: GridPosition) {
        let pad = project.pad(at: position)

        // Vocal pad hold mode: deactivate mic on release
        if pad.isVocalPad && pad.vocalConfig?.activationMode == .hold {
            audioEngine.setMicActive(false)
            isMicActive = false
            midiManager.setLED(at: position, color: pad.color)
            return
        }

        // ... existing release logic (oneShotStopOnRelease check, etc.) unchanged ...
```

- [ ] **Step 5: Wire up scene buttons for dry/wet**

Replace the placeholder `onSideButtonPressed` closure in `setupMIDICallbacks()`:

```swift
        midiManager.onSideButtonPressed = { [weak self] index in
            guard let self, self.vocalPadPosition != nil else { return }
            self.handleDryWetButton(index: index)
        }
```

Add the handler method:

```swift
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
            LaunchpadColor(r: 0, g: 127, b: 20),   // index 0 — green (dry)
            LaunchpadColor(r: 0, g: 100, b: 60),   // index 1
            LaunchpadColor(r: 0, g: 80, b: 90),    // index 2
            LaunchpadColor(r: 0, g: 60, b: 110),   // index 3
            LaunchpadColor(r: 0, g: 40, b: 127),   // index 4
            LaunchpadColor(r: 0, g: 20, b: 127),   // index 5 — blue (wet)
        ]
        let dimColor = LaunchpadColor(r: 8, g: 8, b: 8)

        for i in 0..<6 {
            let color = i < step ? meterColors[i] : dimColor
            midiManager.setSideButtonLED(index: i, color: color)
        }

        // Up/down buttons: white
        let controlColor = LaunchpadColor(r: 60, g: 60, b: 60)
        midiManager.setSideButtonLED(index: 6, color: controlColor) // down
        midiManager.setSideButtonLED(index: 7, color: controlColor) // up
    }
```

- [ ] **Step 6: Update onDeviceConnected to render dry/wet meter**

In `setupMIDICallbacks()`, update the `onDeviceConnected` closure to call `renderDryWetMeter()`:

```swift
        midiManager.onDeviceConnected = { [weak self] in
            guard let self else { return }
            self.midiManager.enterProgrammerMode()
            self.midiManager.syncLEDs(with: self.project, playingPads: self.audioEngine.activePads)
            self.renderDryWetMeter()
        }
```

- [ ] **Step 7: Deactivate mic on Stop All**

In `ContentView.swift`, the "Stop All" button calls `appState.audioEngine.stopAll()`. Also need to deactivate the mic. Add a `stopAll()` method to AppState that handles both:

Actually, simpler: just add to the existing Stop All button action in ContentView. But first, let's add a convenience to AppState:

In AppState, add:

```swift
    func deactivateMic() {
        audioEngine.setMicActive(false)
        isMicActive = false
        if let pos = vocalPadPosition {
            midiManager.setLED(at: pos, color: project.pad(at: pos).color)
        }
    }
```

Then in `ContentView.swift`, update the Stop All button action:

```swift
                        Button {
                            appState.deactivateMic()
                            appState.audioEngine.stopAll()
                            appState.midiManager.syncLEDs(with: appState.project, playingPads: appState.audioEngine.activePads)
                        } label: {
```

- [ ] **Step 8: Sync vocal effect when updating pad config**

In `updatePad(_:at:)`, add effect syncing when a vocal pad's config changes. After the existing body, before `saveProject()`:

```swift
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
```

- [ ] **Step 9: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodegen generate && xcodebuild -scheme Soundboard -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add Soundboard/App/AppState.swift Soundboard/Views/Grid/ContentView.swift
git commit -m "feat: add vocal pad press/release logic and dry/wet scene buttons"
```

---

### Task 6: Vocal Pad UI in PadDetailView

**Files:**
- Modify: `Soundboard/Views/PadDetail/PadDetailView.swift`

- [ ] **Step 1: Add vocal pad detail section**

In `PadDetailView`, the body currently has two branches: `if let sample = pad.sample { ... } else { ... }`. Restructure to three branches. Replace the body's VStack content logic:

After the header `HStack` (which stays unchanged), replace the `if let sample = pad.sample { ... } else { ... }` block with:

```swift
                if pad.isVocalPad, let vocalConfig = pad.vocalConfig {
                    // --- Vocal pad configuration ---

                    // Effect selector
                    DetailSection(title: "EFFECT", icon: "waveform.path.ecg") {
                        HStack(spacing: 6) {
                            ForEach(VocalEffect.allCases) { effect in
                                PlayModeButton(
                                    mode: effect,
                                    isSelected: vocalConfig.effect == effect,
                                    accentColor: accentColor
                                ) {
                                    var p = pad
                                    p.vocalConfig?.effect = effect
                                    appState.updatePad(p, at: position)
                                }
                            }
                        }
                    }

                    // Activation mode
                    DetailSection(title: "ACTIVATION", icon: "hand.tap") {
                        HStack(spacing: 6) {
                            ForEach(VocalActivationMode.allCases) { mode in
                                PlayModeButton(
                                    mode: mode,
                                    isSelected: vocalConfig.activationMode == mode,
                                    accentColor: accentColor
                                ) {
                                    var p = pad
                                    p.vocalConfig?.activationMode = mode
                                    appState.updatePad(p, at: position)
                                }
                            }
                        }
                    }

                    // Dry/Wet slider
                    DetailSection(title: "DRY / WET", icon: "slider.horizontal.3") {
                        HStack(spacing: 8) {
                            Text("Dry")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            Slider(value: Binding(
                                get: { vocalConfig.dryWetMix },
                                set: { newVal in
                                    var p = pad
                                    p.vocalConfig?.dryWetMix = newVal
                                    appState.updatePad(p, at: position)
                                }
                            ), in: 0...1)
                            .tint(accentColor)

                            Text("Wet")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text("\(Int(vocalConfig.dryWetMix * 100))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }

                    // Color
                    DetailSection(title: "COLOR", icon: "paintpalette") {
                        ColorPickerView(color: Binding(
                            get: { pad.color },
                            set: { newColor in
                                var p = pad
                                p.color = newColor
                                appState.updatePad(p, at: position)
                            }
                        ))
                    }

                    // Remove vocal action
                    HStack {
                        Spacer()
                        Button {
                            var p = pad
                            p.vocalConfig = nil
                            p.color = .off
                            appState.updatePad(p, at: position)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("Remove Vocal")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)

                } else if let sample = pad.sample {
                    // --- Existing sample pad sections (unchanged) ---
                    // ... all existing sample UI code stays here exactly as-is ...

                } else {
                    // --- Empty pad ---
                    // ... existing drop target + factory samples stays here ...
```

- [ ] **Step 2: Make PlayModeButton generic**

The existing `PlayModeButton` accepts a `PlayMode` for display. We need it to also work with `VocalEffect` and `VocalActivationMode`. The simplest approach: extract a protocol and make `PlayModeButton` generic.

Add a protocol at the top of `PadDetailView.swift` (or in a separate file if preferred):

```swift
protocol EffectOption: Identifiable {
    var displayName: String { get }
    var iconName: String { get }
}

extension PlayMode: EffectOption {}
extension VocalEffect: EffectOption {}
extension VocalActivationMode: EffectOption {}
```

Then update `PlayModeButton` to be generic:

```swift
struct PlayModeButton<Option: EffectOption>: View {
    let mode: Option
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 14, weight: .medium))

                Text(mode.displayName)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? accentColor.opacity(0.2) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? accentColor.opacity(0.5) : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isSelected ? accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Add "Live Vocal" button to empty pad section**

In the `else` branch (empty pad), add a "Live Vocal" button before the factory samples section:

```swift
                } else {
                    // Empty pad — drop target
                    VStack(spacing: 14) {
                        // ... existing drop icon ...
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)

                    // Live Vocal button
                    DetailSection(title: "LIVE VOCAL", icon: "mic.fill") {
                        Button {
                            assignVocalPad()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.purple)

                                Text("Assign as Live Vocal")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Spacer()

                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.purple.opacity(0.6))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.purple.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Factory samples
                    DetailSection(title: "FACTORY SAMPLES", icon: "waveform.circle") {
                        // ... existing factory samples code unchanged ...
                    }
                }
```

- [ ] **Step 4: Add assignVocalPad() helper method**

Add this method to PadDetailView:

```swift
    private func assignVocalPad() {
        // If another pad is already vocal, clear it
        if let existingPos = appState.vocalPadPosition, existingPos != position {
            var oldPad = appState.project.pad(at: existingPos)
            oldPad.vocalConfig = nil
            oldPad.color = .off
            appState.updatePad(oldPad, at: existingPos)
        }

        var padConfig = pad
        padConfig.vocalConfig = VocalPadConfig()
        padConfig.sample = nil // mutual exclusion
        padConfig.color = LaunchpadColor(r: 127, g: 0, b: 80) // magenta
        appState.updatePad(padConfig, at: position)
    }
```

- [ ] **Step 5: Update header for vocal pad**

In the header section, update the name display to show "Live Vocal" for vocal pads. Change the header:

```swift
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PAD \(position.row + 1).\(position.column + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .tracking(1.5)

                        if pad.isVocalPad {
                            HStack(spacing: 4) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 14))
                                Text("Live Vocal")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.purple)
                        } else if let sample = pad.sample {
                            Text(sample.name)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        } else {
                            Text("Empty Pad")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
```

- [ ] **Step 6: Update accentColor for vocal pads**

Update the `accentColor` computed property:

```swift
    private var accentColor: Color {
        if pad.isVocalPad { return .purple }
        return pad.isEmpty ? .blue : pad.color.swiftUIColor
    }
```

- [ ] **Step 7: Handle file drop on vocal pad**

The existing `dropDestination` on PadDetailView's body handles file drops. When dropping a file on a vocal pad, it should convert back to a sample pad. The existing `importFile(url:)` method sets `padConfig.sample = sample` but doesn't clear `vocalConfig`. Update it:

```swift
    private func importFile(url: URL) -> Bool {
        guard let sample = try? appState.sampleStore.importAudioFile(from: url) else {
            return false
        }
        var padConfig = pad
        padConfig.sample = sample
        padConfig.vocalConfig = nil // clear vocal if present
        if padConfig.color == .off {
            padConfig.color = .defaultLoaded
        }
        appState.updatePad(padConfig, at: position)
        return true
    }
```

- [ ] **Step 8: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodegen generate && xcodebuild -scheme Soundboard -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
git add Soundboard/Views/PadDetail/PadDetailView.swift
git commit -m "feat: add vocal pad configuration UI and live vocal assignment"
```

---

### Task 7: Add Mic Gain to SettingsView

**Files:**
- Modify: `Soundboard/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Add Microphone section to SettingsView**

Add a new tab to the TabView in SettingsView, after the existing tabs:

```swift
    var body: some View {
        TabView {
            midiTab
                .tabItem { Label("MIDI", systemImage: "pianokeys") }

            audioTab
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }

            projectsTab
                .tabItem { Label("Projects", systemImage: "folder") }
        }
        .frame(width: 450, height: 350)
    }
```

Add the `audioTab` computed property:

```swift
    // MARK: - Audio Tab

    private var audioTab: some View {
        Form {
            Section("Microphone") {
                HStack(spacing: 8) {
                    Image(systemName: micGainIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Slider(
                        value: Binding(
                            get: { appState.micGain },
                            set: { appState.micGain = $0 }
                        ),
                        in: 0...2,
                        step: 0.05
                    )

                    Text("\(Int(appState.micGain * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                Text("Adjusts microphone input gain for live vocal pads.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    private var micGainIcon: String {
        if appState.micGain == 0 { return "mic.slash" }
        if appState.micGain < 0.5 { return "mic" }
        return "mic.fill"
    }
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodegen generate && xcodebuild -scheme Soundboard -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Soundboard/Views/Settings/SettingsView.swift
git commit -m "feat: add microphone gain slider to settings"
```

---

### Task 8: Update PadView for Vocal Pads

**Files:**
- Modify: `Soundboard/Views/Grid/PadView.swift`

- [ ] **Step 1: Update pad content to show mic icon for vocal pads**

In `PadView`, update the content VStack to handle vocal pads. Replace the current content section (lines 74-101):

```swift
            // Content
            VStack(spacing: 0) {
                if pad.isVocalPad {
                    Spacer(minLength: 0)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

                    Text("VOCAL")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(1)

                    Spacer(minLength: 0)
                } else if let sample = pad.sample {
                    Spacer(minLength: 0)

                    if let emoji = pad.emoji {
                        Text(emoji)
                            .font(.system(size: 28))
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    }

                    Text(sample.name)
                        .font(.system(size: pad.emoji != nil ? 10 : 13, weight: .semibold, design: .rounded))
                        .lineLimit(pad.emoji != nil ? 1 : 2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(pad.emoji != nil ? 0.7 : 1.0))
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)

                    Spacer(minLength: 0)

                    Text(formatDuration(sample.effectiveDuration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                } else {
                    // Empty pad — subtle plus icon
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.white.opacity(isHovering ? 0.25 : 0.08))
                }
            }
            .padding(4)
```

- [ ] **Step 2: Update importFile to clear vocalConfig on file drop**

In PadView's `importFile(url:)` method (lines 201-212), add `vocalConfig = nil`:

```swift
    private func importFile(url: URL) -> Bool {
        guard let sample = try? appState.sampleStore.importAudioFile(from: url) else {
            return false
        }
        var padConfig = pad
        padConfig.sample = sample
        padConfig.vocalConfig = nil
        if padConfig.color == .off {
            padConfig.color = .defaultLoaded
        }
        appState.updatePad(padConfig, at: position)
        return true
    }
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodegen generate && xcodebuild -scheme Soundboard -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Soundboard/Views/Grid/PadView.swift
git commit -m "feat: show mic icon on vocal pads in grid view"
```

---

### Task 9: Add LaunchpadColor Vocal Default

**Files:**
- Modify: `Soundboard/Models/LaunchpadColor.swift`

- [ ] **Step 1: Add vocal color constant**

Add a static constant for the default vocal pad color in `LaunchpadColor.swift`:

```swift
    static let vocal = LaunchpadColor(r: 127, g: 0, b: 80)
```

Add it after the existing `recording` constant (line 19).

- [ ] **Step 2: Use the constant**

Update `PadDetailView.assignVocalPad()` to use `.vocal` instead of the inline literal. And update `AppState.renderDryWetMeter()` if needed.

In `PadDetailView.assignVocalPad()`:
```swift
        padConfig.color = .vocal
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodegen generate && xcodebuild -scheme Soundboard -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Soundboard/Models/LaunchpadColor.swift Soundboard/Views/PadDetail/PadDetailView.swift
git commit -m "feat: add LaunchpadColor.vocal default for vocal pads"
```

---

### Task 10: Final Build Verification

- [ ] **Step 1: Clean build**

Run: `cd /Users/simonflore/Code/soundboard && xcodegen generate && xcodebuild -scheme Soundboard -configuration Debug clean build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Verify no compiler warnings related to changes**

Run: `cd /Users/simonflore/Code/soundboard && xcodebuild -scheme Soundboard -configuration Debug build 2>&1 | grep -i "warning:" | grep -v "DSWaveformImage" | head -20`
Expected: No warnings from Soundboard source files

- [ ] **Step 3: Smoke test checklist**

Launch the app and manually verify:
1. Empty pad shows "Assign as Live Vocal" button
2. Clicking it creates a vocal pad with magenta color and mic icon
3. Vocal pad detail shows Effect, Activation, Dry/Wet, Color sections
4. Scene buttons on Launchpad show dry/wet meter (if connected)
5. Pressing vocal pad on Launchpad gates the mic (test with headphones)
6. Settings → Audio tab shows mic gain slider
7. Recording still works (create a sample, assign to a pad)
8. Stop All deactivates the mic

---

## File Summary

**New files (3):**
- `Soundboard/Models/VocalEffect.swift`
- `Soundboard/Models/VocalActivationMode.swift`
- `Soundboard/Models/VocalPadConfig.swift`

**Modified files (9):**
- `Soundboard/Models/PadConfiguration.swift` — add `vocalConfig`, `isVocalPad`, update `isEmpty`
- `Soundboard/Models/Project.swift` — update `swapPads` to include `vocalConfig`
- `Soundboard/Models/AppMode.swift` — remove `xyPad` case
- `Soundboard/Models/LaunchpadColor.swift` — add `.vocal` constant
- `Soundboard/Managers/AudioEngine.swift` — add mic chain, effect nodes, control methods; remove XY-only methods
- `Soundboard/App/AppState.swift` — remove XY mode; add vocal pad press/release, dry/wet scene buttons, mic gain
- `Soundboard/Views/Grid/GridView.swift` — remove XY overlay
- `Soundboard/Views/Grid/ContentView.swift` — remove XY button, update Stop All
- `Soundboard/Views/Grid/PadView.swift` — add vocal pad icon, clear vocalConfig on file drop
- `Soundboard/Views/PadDetail/PadDetailView.swift` — vocal pad config UI, generic PlayModeButton, assign vocal button
- `Soundboard/Views/Settings/SettingsView.swift` — add Audio tab with mic gain slider
