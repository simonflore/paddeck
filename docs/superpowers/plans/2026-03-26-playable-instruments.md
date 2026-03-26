# Playable Instruments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 5 playable instruments (Piano, Drums, Marimba, Synth Lead, Synth Pad) to PadDeck so pads can be configured as instrument triggers that transform the Launchpad grid into a playable note layout.

**Architecture:** New `InstrumentEngine` manager owns `AVAudioUnitSampler` instances (one per instrument), connected to the existing `AudioEngine` mixer. `InstrumentType` enum defines note layouts and LED color schemes per instrument. `AppState` gains an `activeInstrument` mode that reroutes pad press/release to instrument note playback.

**Tech Stack:** AVAudioUnitSampler, SoundFont (.sf2), SwiftUI, CoreMIDI (existing)

**Spec:** `docs/superpowers/specs/2026-03-26-playable-instruments-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `PadDeck/Models/InstrumentType.swift` | Enum with 5 cases, display properties, `EffectOption` conformance, `NoteLayout` factory |
| `PadDeck/Models/InstrumentConfig.swift` | Codable config struct (instrument type + volume) |
| `PadDeck/Models/NoteLayout.swift` | Struct mapping GridPosition → MIDI note + LED colors |
| `PadDeck/Managers/InstrumentEngine.swift` | AVAudioUnitSampler lifecycle, note playback, SoundFont loading |
| `PadDeck/Views/Grid/InstrumentStatusBar.swift` | Minimal floating banner shown during instrument mode |
| `PadDeck/Resources/SoundFonts/*.sf2` | 5 SoundFont files (user-sourced) |

### Modified Files

| File | Changes |
|------|---------|
| `PadDeck/Models/PadConfiguration.swift` | Add `instrumentConfig: InstrumentConfig?`, `isInstrumentPad`, update `isEmpty` |
| `PadDeck/Managers/AudioEngine.swift` | Expose `mixerNode` and `audioEngine` as read-only properties |
| `PadDeck/App/AppState.swift` | Add `ActiveInstrument` struct, `activeInstrument` state, `instrumentEngine`, instrument mode in `handlePadPress`/`handlePadRelease`, side button routing, `exitInstrumentMode()`, `renderInstrumentGrid()` |
| `PadDeck/Views/Grid/PadView.swift` | Show instrument icon for instrument pads |
| `PadDeck/Views/Grid/GridView.swift` | Add `InstrumentStatusBar` overlay |
| `PadDeck/Views/PadDetail/PadDetailView.swift` | Instrument assignment section (empty pad), instrument pad editor |
| `PadDeck/CLAUDE.md` | Document instrument architecture |

---

### Task 1: Create NoteLayout and InstrumentType models

**Files:**
- Create: `PadDeck/Models/NoteLayout.swift`
- Create: `PadDeck/Models/InstrumentType.swift`

- [ ] **Step 1: Create NoteLayout struct**

Create `PadDeck/Models/NoteLayout.swift`:

```swift
import Foundation

struct NoteLayout {
    /// Returns the MIDI note for a grid position, or nil if the pad is inactive.
    let noteForPosition: (GridPosition) -> UInt8?

    /// Returns the LED color for a grid position (rest state).
    let colorForPosition: (GridPosition) -> LaunchpadColor

    /// Color to show when a pad is pressed.
    let pressedColor: LaunchpadColor
}
```

- [ ] **Step 2: Create InstrumentType enum with display properties**

Create `PadDeck/Models/InstrumentType.swift`:

```swift
import Foundation

enum InstrumentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case piano
    case drums
    case marimba
    case synthLead
    case synthPad

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .piano: "Piano"
        case .drums: "Drums"
        case .marimba: "Marimba"
        case .synthLead: "Synth Lead"
        case .synthPad: "Synth Pad"
        }
    }

    var iconName: String {
        switch self {
        case .piano: "pianokeys"
        case .drums: "drum.fill"
        case .marimba: "music.quarternote.3"
        case .synthLead: "waveform"
        case .synthPad: "waveform.path"
        }
    }

    var soundFontFilename: String {
        switch self {
        case .piano: "Piano"
        case .drums: "Drums"
        case .marimba: "Marimba"
        case .synthLead: "SynthLead"
        case .synthPad: "SynthPad"
        }
    }

    var defaultColor: LaunchpadColor {
        switch self {
        case .piano: LaunchpadColor(r: 100, g: 100, b: 127)
        case .drums: LaunchpadColor(r: 127, g: 40, b: 0)
        case .marimba: LaunchpadColor(r: 127, g: 70, b: 10)
        case .synthLead: LaunchpadColor(r: 0, g: 127, b: 30)
        case .synthPad: LaunchpadColor(r: 100, g: 0, b: 127)
        }
    }
}

// Conform to EffectOption (defined in PadDetailView) for reuse in type selector UI
extension InstrumentType: EffectOption {}
```

- [ ] **Step 3: Add NoteLayout factory computed property to InstrumentType**

Add to `PadDeck/Models/InstrumentType.swift`, below the `defaultColor` property:

```swift
    var noteLayout: NoteLayout {
        switch self {
        case .piano: Self.pianoLayout()
        case .drums: Self.drumsLayout()
        case .marimba: Self.marimbaLayout()
        case .synthLead: Self.isomorphicLayout(base: 48, brightColor: LaunchpadColor(r: 0, g: 127, b: 30), dimColor: LaunchpadColor(r: 0, g: 40, b: 10))
        case .synthPad: Self.isomorphicLayout(base: 36, brightColor: LaunchpadColor(r: 100, g: 0, b: 127), dimColor: LaunchpadColor(r: 30, g: 0, b: 50))
        }
    }
```

Then add the private static factory methods below the enum closing brace but still inside the file:

```swift
// MARK: - Note Layouts

private extension InstrumentType {
    /// Black key semitones within an octave: C#=1, D#=3, F#=6, G#=8, A#=10
    static let blackKeys: Set<UInt8> = [1, 3, 6, 8, 10]

    // MARK: Piano — chromatic, 1 octave per row, starting at C1 (MIDI 24)

    static func pianoLayout() -> NoteLayout {
        NoteLayout(
            noteForPosition: { pos in
                let note = 24 + (pos.row * 12) + pos.column
                guard note <= 108 else { return nil }  // Clamp at C8
                return UInt8(note)
            },
            colorForPosition: { pos in
                let note = 24 + (pos.row * 12) + pos.column
                guard note <= 108 else { return .off }
                let semitone = UInt8(note % 12)
                return blackKeys.contains(semitone)
                    ? LaunchpadColor(r: 15, g: 15, b: 60)
                    : LaunchpadColor(r: 100, g: 100, b: 100)
            },
            pressedColor: LaunchpadColor(r: 127, g: 127, b: 127)
        )
    }

    // MARK: Drums — 4×4 bottom-left quadrant mapped to GM percussion

    static func drumsLayout() -> NoteLayout {
        // Grid[row][col] → GM drum MIDI note
        // Row 0 (bottom), Row 3 (top of quadrant)
        let drumGrid: [[UInt8]] = [
            [36, 35, 40, 43],  // Row 0: Kick, Kick2, SideStick, FloorTom
            [38, 39, 37, 75],  // Row 1: Snare, Clap, Rimshot, Clave
            [50, 47, 45, 56],  // Row 2: HiTom, MidTom, LowTom, Cowbell
            [49, 51, 46, 42],  // Row 3: Crash, Ride, OpenHH, ClosedHH
        ]

        // Color per drum note category
        let drumColor: (UInt8) -> LaunchpadColor = { note in
            switch note {
            case 35, 36: return LaunchpadColor(r: 127, g: 20, b: 0)    // Kicks: red
            case 37, 38, 39, 40: return LaunchpadColor(r: 127, g: 60, b: 0) // Snares: orange
            case 42, 44, 46: return LaunchpadColor(r: 127, g: 127, b: 0)   // Hi-hats: yellow
            case 49, 51, 52, 55: return LaunchpadColor(r: 0, g: 127, b: 127) // Cymbals: cyan
            case 43, 45, 47, 48, 50: return LaunchpadColor(r: 0, g: 127, b: 20) // Toms: green
            default: return LaunchpadColor(r: 80, g: 0, b: 127)             // Percussion: purple
            }
        }

        return NoteLayout(
            noteForPosition: { pos in
                guard pos.row < 4, pos.column < 4 else { return nil }
                return drumGrid[pos.row][pos.column]
            },
            colorForPosition: { pos in
                guard pos.row < 4, pos.column < 4 else { return .off }
                return drumColor(drumGrid[pos.row][pos.column])
            },
            pressedColor: LaunchpadColor(r: 127, g: 127, b: 127)
        )
    }

    // MARK: Marimba — chromatic, 1 octave per row, starting at F2 (MIDI 41)

    static func marimbaLayout() -> NoteLayout {
        NoteLayout(
            noteForPosition: { pos in
                let note = 41 + (pos.row * 12) + pos.column
                guard note <= 127 else { return nil }
                return UInt8(note)
            },
            colorForPosition: { pos in
                let note = 41 + (pos.row * 12) + pos.column
                guard note <= 127 else { return .off }
                let semitone = UInt8(note % 12)
                return blackKeys.contains(semitone)
                    ? LaunchpadColor(r: 50, g: 25, b: 5)
                    : LaunchpadColor(r: 127, g: 70, b: 10)
            },
            pressedColor: LaunchpadColor(r: 127, g: 120, b: 80)
        )
    }

    // MARK: Isomorphic 4ths — each row +5 semitones (used by Synth Lead and Synth Pad)

    static func isomorphicLayout(base: Int, brightColor: LaunchpadColor, dimColor: LaunchpadColor) -> NoteLayout {
        NoteLayout(
            noteForPosition: { pos in
                let note = base + (pos.row * 5) + pos.column
                guard note <= 127 else { return nil }
                return UInt8(note)
            },
            colorForPosition: { pos in
                let note = base + (pos.row * 5) + pos.column
                guard note <= 127 else { return .off }
                return pos.column == 0 ? brightColor : dimColor
            },
            pressedColor: LaunchpadColor(r: 127, g: 127, b: 127)
        )
    }
}
```

- [ ] **Step 4: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodebuild -project build/PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add PadDeck/Models/NoteLayout.swift PadDeck/Models/InstrumentType.swift
git commit -m "feat: add InstrumentType enum and NoteLayout for grid mapping"
```

---

### Task 2: Create InstrumentConfig and modify PadConfiguration

**Files:**
- Create: `PadDeck/Models/InstrumentConfig.swift`
- Modify: `PadDeck/Models/PadConfiguration.swift`

- [ ] **Step 1: Create InstrumentConfig struct**

Create `PadDeck/Models/InstrumentConfig.swift`:

```swift
import Foundation

struct InstrumentConfig: Codable, Equatable, Sendable {
    var instrumentType: InstrumentType
    var volume: Float

    init(instrumentType: InstrumentType, volume: Float = 0.8) {
        self.instrumentType = instrumentType
        self.volume = volume
    }
}
```

- [ ] **Step 2: Add instrumentConfig to PadConfiguration**

In `PadDeck/Models/PadConfiguration.swift`, add the property, computed helpers, and update the initializers:

```swift
struct PadConfiguration: Codable, Identifiable, Sendable {
    let position: GridPosition
    var sample: Sample?
    var color: LaunchpadColor
    var playMode: PlayMode
    var volume: Float
    var emoji: String?
    var vocalConfig: VocalPadConfig?
    var instrumentConfig: InstrumentConfig?

    var id: Int { position.id }
    var isEmpty: Bool { sample == nil && vocalConfig == nil && instrumentConfig == nil }
    var isVocalPad: Bool { vocalConfig != nil }
    var isInstrumentPad: Bool { instrumentConfig != nil }

    init(position: GridPosition) {
        self.position = position
        self.sample = nil
        self.color = .off
        self.playMode = .oneShot
        self.volume = 1.0
        self.emoji = nil
        self.vocalConfig = nil
        self.instrumentConfig = nil
    }

    init(position: GridPosition, sample: Sample?, color: LaunchpadColor, playMode: PlayMode, volume: Float, emoji: String? = nil, vocalConfig: VocalPadConfig? = nil, instrumentConfig: InstrumentConfig? = nil) {
        self.position = position
        self.sample = sample
        self.color = color
        self.playMode = playMode
        self.volume = volume
        self.emoji = emoji
        self.vocalConfig = vocalConfig
        self.instrumentConfig = instrumentConfig
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodebuild -project build/PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add PadDeck/Models/InstrumentConfig.swift PadDeck/Models/PadConfiguration.swift
git commit -m "feat: add InstrumentConfig and instrument pad support to PadConfiguration"
```

---

### Task 3: Expose AudioEngine internals and create InstrumentEngine

**Files:**
- Modify: `PadDeck/Managers/AudioEngine.swift`
- Create: `PadDeck/Managers/InstrumentEngine.swift`

- [ ] **Step 1: Expose mixer and engine on AudioEngine**

In `PadDeck/Managers/AudioEngine.swift`, add two read-only computed properties right after the existing stored properties (after line 15: `private var loopBufferCache`):

```swift
    /// Exposed for InstrumentEngine to attach sampler nodes.
    var mixerNode: AVAudioMixerNode { mixer }
    var avAudioEngine: AVAudioEngine { engine }
```

- [ ] **Step 2: Create InstrumentEngine**

Create `PadDeck/Managers/InstrumentEngine.swift`:

```swift
import AVFoundation
import Foundation

@Observable
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
        // masterGain is in dB. Map 0-1 linear to -60..0 dB (mute at 0, full at 1).
        if volume <= 0 {
            sampler.masterGain = -90
        } else {
            sampler.masterGain = 20 * log10(volume)
        }
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodebuild -project build/PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add PadDeck/Managers/AudioEngine.swift PadDeck/Managers/InstrumentEngine.swift
git commit -m "feat: add InstrumentEngine with AVAudioUnitSampler playback"
```

---

### Task 4: Add instrument mode to AppState

**Files:**
- Modify: `PadDeck/App/AppState.swift`

- [ ] **Step 1: Add ActiveInstrument struct and new properties**

In `PadDeck/App/AppState.swift`, add the nested struct before the `AppState` class, and new properties inside the class:

Add before `@Observable final class AppState {`:

```swift
struct ActiveInstrument {
    let type: InstrumentType
    let sourcePosition: GridPosition
}
```

Add after `var isEditMode = false` (line 12):

```swift
    var activeInstrument: ActiveInstrument?
```

Add after `let textScroller: TextScroller` (line 33):

```swift
    let instrumentEngine: InstrumentEngine
```

- [ ] **Step 2: Initialize InstrumentEngine in init()**

In the `init()` method, after `self.textScroller = TextScroller(midiManager: midi)` (line 44), add:

```swift
        self.instrumentEngine = InstrumentEngine(audioEngine: self.audioEngine)
```

- [ ] **Step 3: Add instrument mode routing to handlePadPress**

In `handlePadPress(position:velocity:)`, add two blocks at the very top of the method, before the existing vocal pad check (before line 108 `let pad = project.pad(at: position)`):

```swift
        // Instrument mode: route all pads to note playback
        if let active = activeInstrument {
            let layout = active.type.noteLayout
            guard let note = layout.noteForPosition(position) else { return }
            instrumentEngine.playNote(note: note, velocity: velocity, instrument: active.type)
            midiManager.setLED(at: position, color: layout.pressedColor)
            return
        }
```

Then after `let pad = project.pad(at: position)` and before the vocal pad check, add:

```swift
        // Instrument pad: enter instrument mode
        if pad.isInstrumentPad, let config = pad.instrumentConfig {
            activeInstrument = ActiveInstrument(type: config.instrumentType, sourcePosition: position)
            instrumentEngine.loadInstrument(config.instrumentType)
            instrumentEngine.setVolume(config.volume, for: config.instrumentType)
            renderInstrumentGrid(config.instrumentType)
            return
        }
```

- [ ] **Step 4: Add instrument mode routing to handlePadRelease**

In `handlePadRelease(position:)`, add at the very top of the method, before `let pad = project.pad(at: position)`:

```swift
        // Instrument mode: send note-off
        if let active = activeInstrument {
            let layout = active.type.noteLayout
            guard let note = layout.noteForPosition(position) else { return }
            instrumentEngine.stopNote(note: note, instrument: active.type)
            midiManager.setLED(at: position, color: layout.colorForPosition(position))
            return
        }
```

- [ ] **Step 5: Add exitInstrumentMode and renderInstrumentGrid methods**

Add these methods to AppState, after the `deactivateMic()` method:

```swift
    // MARK: - Instrument Mode

    func exitInstrumentMode() {
        instrumentEngine.stopAllNotes()
        activeInstrument = nil
        midiManager.syncLEDs(with: project, playingPads: audioEngine.activePads)
        renderDryWetMeter()
    }

    func renderInstrumentGrid(_ type: InstrumentType) {
        let layout = type.noteLayout
        var entries: [(note: UInt8, r: UInt8, g: UInt8, b: UInt8)] = []
        for row in 0..<8 {
            for col in 0..<8 {
                let pos = GridPosition(row: row, column: col)
                let color = layout.colorForPosition(pos)
                entries.append((note: pos.midiNote, r: color.r, g: color.g, b: color.b))
            }
        }
        midiManager.sendBatchLEDs(entries: entries)

        // Side buttons: only top button lit (exit = red)
        for i in 0..<7 {
            midiManager.setSideButtonLED(index: i, color: .off)
        }
        midiManager.setSideButtonLED(index: 7, color: LaunchpadColor(r: 127, g: 20, b: 20))
    }
```

- [ ] **Step 6: Update side button handling in setupMIDICallbacks**

Replace the `onSideButtonPressed` closure in `setupMIDICallbacks()` with:

```swift
        midiManager.onSideButtonPressed = { [weak self] index in
            guard let self else { return }
            // Instrument mode: top button exits, all others swallowed
            if self.activeInstrument != nil {
                if index == 7 {
                    self.exitInstrumentMode()
                }
                return
            }
            guard self.vocalPadPosition != nil else { return }
            self.handleDryWetButton(index: index)
        }
```

- [ ] **Step 7: Exit instrument mode on project switch and stop-all**

In `switchProject(_:)`, add `exitInstrumentMode()` call before `deactivateMic()` (if `activeInstrument` is set):

```swift
    func switchProject(_ newProject: Project) {
        if activeInstrument != nil {
            exitInstrumentMode()
        }
        deactivateMic()
        audioEngine.stopAll()
        project = newProject
        selectedPad = nil
        refreshVocalPadPosition()
        midiManager.syncLEDs(with: project, playingPads: audioEngine.activePads)
        renderDryWetMeter()
    }
```

- [ ] **Step 8: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodebuild -project build/PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
git add PadDeck/App/AppState.swift
git commit -m "feat: add instrument mode to AppState with pad press/release routing"
```

---

### Task 5: Update PadView to show instrument indicator

**Files:**
- Modify: `PadDeck/Views/Grid/PadView.swift`

- [ ] **Step 1: Add instrument pad content to PadView**

In `PadDeck/Views/Grid/PadView.swift`, in the `VStack(spacing: 0)` content block, add a new branch after the vocal pad check (`if pad.isVocalPad { ... }`) and before the sample check (`} else if let sample = pad.sample {`):

```swift
                } else if pad.isInstrumentPad, let config = pad.instrumentConfig {
                    Spacer(minLength: 0)

                    Image(systemName: config.instrumentType.iconName)
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

                    Text(config.instrumentType.displayName.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(1)
                        .lineLimit(1)

                    Spacer(minLength: 0)
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodebuild -project build/PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PadDeck/Views/Grid/PadView.swift
git commit -m "feat: show instrument icon and name on instrument pads"
```

---

### Task 6: Add InstrumentStatusBar and GridView overlay

**Files:**
- Create: `PadDeck/Views/Grid/InstrumentStatusBar.swift`
- Modify: `PadDeck/Views/Grid/GridView.swift`

- [ ] **Step 1: Create InstrumentStatusBar view**

Create `PadDeck/Views/Grid/InstrumentStatusBar.swift`:

```swift
import SwiftUI

struct InstrumentStatusBar: View {
    let instrumentType: InstrumentType
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: instrumentType.iconName)
                .font(.system(size: 14, weight: .medium))

            Text(instrumentType.displayName)
                .font(.system(size: 14, weight: .bold, design: .rounded))

            Spacer()

            Button(action: onExit) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Exit")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(instrumentType.defaultColor.swiftUIColor)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(instrumentType.defaultColor.swiftUIColor.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }
}
```

- [ ] **Step 2: Add overlay to GridView**

In `PadDeck/Views/Grid/GridView.swift`, add an overlay to the outer `VStack` after the existing `.overlay(alignment: .bottomTrailing)` block (after the drag hint overlay) and before `.padding(14)`:

```swift
        .overlay(alignment: .top) {
            if let active = appState.activeInstrument {
                InstrumentStatusBar(
                    instrumentType: active.type,
                    onExit: { appState.exitInstrumentMode() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appState.activeInstrument != nil)
            }
        }
```

Note: This requires `activeInstrument != nil` comparison. Since `ActiveInstrument` doesn't conform to `Equatable`, use the nil check for the animation value.

- [ ] **Step 3: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodebuild -project build/PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add PadDeck/Views/Grid/InstrumentStatusBar.swift PadDeck/Views/Grid/GridView.swift
git commit -m "feat: add instrument mode status bar overlay to grid"
```

---

### Task 7: Add instrument sections to PadDetailView

**Files:**
- Modify: `PadDeck/Views/PadDetail/PadDetailView.swift`

- [ ] **Step 1: Add instrument pad editor branch**

In `PadDeck/Views/PadDetail/PadDetailView.swift`, the main body has three branches:
1. `if pad.isVocalPad` (line 89)
2. `} else if let sample = pad.sample {` (line 191)
3. `} else {` — empty pad (line 378)

Add a new branch after the vocal pad block and before the sample block. Change `} else if let sample = pad.sample {` to:

```swift
                } else if pad.isInstrumentPad, let instrumentConfig = pad.instrumentConfig {
                    // Instrument type selector
                    DetailSection(title: "INSTRUMENT", icon: "pianokeys") {
                        HStack(spacing: 6) {
                            ForEach(InstrumentType.allCases) { type in
                                PlayModeButton(
                                    mode: type,
                                    isSelected: instrumentConfig.instrumentType == type,
                                    accentColor: accentColor
                                ) {
                                    var p = pad
                                    p.instrumentConfig?.instrumentType = type
                                    p.color = type.defaultColor
                                    appState.updatePad(p, at: position)
                                }
                            }
                        }
                    }

                    // Volume
                    DetailSection(title: "VOLUME", icon: "speaker.wave.2") {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            Slider(value: Binding(
                                get: { instrumentConfig.volume },
                                set: { newVol in
                                    var p = pad
                                    p.instrumentConfig?.volume = newVol
                                    appState.updatePad(p, at: position)
                                }
                            ), in: 0...1)
                            .tint(accentColor)

                            Text("\(Int(instrumentConfig.volume * 100))%")
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

                    // Remove instrument action
                    HStack {
                        Spacer()
                        Button {
                            var p = pad
                            p.instrumentConfig = nil
                            p.color = .off
                            appState.updatePad(p, at: position)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("Remove Instrument")
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
```

- [ ] **Step 2: Update the header to show instrument info**

In the header section at the top of the body, update the `VStack(alignment: .leading, spacing: 2)` to add an instrument branch. After the vocal pad header check (`if pad.isVocalPad { ... }`) and before the sample check (`} else if let sample = pad.sample {`), add:

```swift
                        } else if pad.isInstrumentPad, let config = pad.instrumentConfig {
                            HStack(spacing: 4) {
                                Image(systemName: config.instrumentType.iconName)
                                    .font(.system(size: 14))
                                Text(config.instrumentType.displayName)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(accentColor)
```

- [ ] **Step 3: Update accentColor for instrument pads**

In the `accentColor` computed property, add an instrument check. Change:

```swift
    private var accentColor: Color {
        if pad.isVocalPad { return .purple }
        return pad.isEmpty ? .blue : pad.color.swiftUIColor
    }
```

to:

```swift
    private var accentColor: Color {
        if pad.isVocalPad { return .purple }
        if pad.isInstrumentPad { return pad.color.swiftUIColor }
        return pad.isEmpty ? .blue : pad.color.swiftUIColor
    }
```

- [ ] **Step 4: Add instrument assignment section to empty pad view**

In the empty pad section (the `} else {` block), after the "LIVE VOCAL" `DetailSection` and before the "FACTORY SAMPLES" `DetailSection`, add:

```swift
                    // Instrument assignment
                    DetailSection(title: "INSTRUMENT", icon: "pianokeys") {
                        VStack(spacing: 6) {
                            ForEach(InstrumentType.allCases) { type in
                                Button {
                                    assignInstrumentPad(type)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: type.iconName)
                                            .font(.system(size: 14))
                                            .foregroundStyle(type.defaultColor.swiftUIColor)
                                            .frame(width: 20)

                                        Text(type.displayName)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(type.defaultColor.swiftUIColor.opacity(0.6))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.white.opacity(0.03))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
```

- [ ] **Step 5: Add assignInstrumentPad helper method**

Add this method to PadDetailView, after the `assignVocalPad()` method:

```swift
    private func assignInstrumentPad(_ type: InstrumentType) {
        var padConfig = pad
        padConfig.instrumentConfig = InstrumentConfig(instrumentType: type)
        padConfig.sample = nil
        padConfig.vocalConfig = nil
        padConfig.color = type.defaultColor
        appState.updatePad(padConfig, at: position)
    }
```

- [ ] **Step 6: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodebuild -project build/PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add PadDeck/Views/PadDetail/PadDetailView.swift
git commit -m "feat: add instrument assignment and editor UI to PadDetailView"
```

---

### Task 8: Add SoundFont assets and regenerate Xcode project

**Files:**
- Create: `PadDeck/Resources/SoundFonts/` directory
- Modify: `project.yml` (if needed for resource inclusion)

- [ ] **Step 1: Create SoundFonts directory**

```bash
mkdir -p PadDeck/Resources/SoundFonts
```

- [ ] **Step 2: Source and add SoundFont files**

You need 5 `.sf2` files placed in `PadDeck/Resources/SoundFonts/`:
- `Piano.sf2` — Acoustic Grand Piano (GM Program 0)
- `Drums.sf2` — Standard Drum Kit (GM Percussion)
- `Marimba.sf2` — Marimba (GM Program 12)
- `SynthLead.sf2` — Synth Lead (GM Program 80 or similar soft lead)
- `SynthPad.sf2` — Synth Pad (GM Program 88 or similar warm pad)

**Free sources:**
- **MuseScore General** (musescore.org) — high quality, MIT license, ~40MB full GM (extract individual instruments using a tool like Polyphone)
- **FluidR3_GM** — GPL, commonly available, can extract individual instruments
- **Polyphone** (polyphone-soundfonts.com) — SF2 editor to extract/create individual instrument SoundFonts from larger GM banks

Alternatively, use a single full GM SoundFont and select programs by number. To do this:
1. Place a single `GeneralMIDI.sf2` in the SoundFonts directory
2. Update `InstrumentType.soundFontFilename` to return `"GeneralMIDI"` for all cases
3. Update `InstrumentEngine.loadInstrument` to pass the correct GM program number per type:
   - Piano: program 0
   - Drums: program 0 with `kAUSampler_DefaultPercussionBankMSB`
   - Marimba: program 12
   - Synth Lead: program 80
   - Synth Pad: program 88

- [ ] **Step 3: Verify XcodeGen includes the resources**

Since `project.yml` uses `sources: - path: PadDeck` and XcodeGen includes all files under that path, the `.sf2` files will be included automatically as bundle resources. No `project.yml` change is needed.

Regenerate the Xcode project:

```bash
cd /Users/simonflore/Code/soundboard && xcodegen generate
```

- [ ] **Step 4: Build to verify SoundFonts are bundled**

Run: `cd /Users/simonflore/Code/soundboard && xcodebuild -project build/PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

If SoundFont files are not yet added, the build will still succeed — the engine prints a warning to console when files are missing but does not crash.

- [ ] **Step 5: Commit**

```bash
git add PadDeck/Resources/SoundFonts/
git commit -m "chore: add SoundFont assets for playable instruments"
```

---

### Task 9: Handle Stop All and edit mode guards

**Files:**
- Modify: `PadDeck/Views/Grid/ContentView.swift`

- [ ] **Step 1: Exit instrument mode on Stop All**

In `PadDeck/Views/Grid/ContentView.swift`, update the Stop All button action (around line 90) to also exit instrument mode:

```swift
                    // Stop All button
                    Button {
                        if appState.activeInstrument != nil {
                            appState.exitInstrumentMode()
                        }
                        appState.deactivateMic()
                        appState.audioEngine.stopAll()
                        appState.midiManager.syncLEDs(with: appState.project, playingPads: appState.audioEngine.activePads)
                    } label: {
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/simonflore/Code/soundboard && xcodebuild -project build/PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PadDeck/Views/Grid/ContentView.swift
git commit -m "feat: exit instrument mode on Stop All"
```

---

### Task 10: Update CLAUDE.md

**Files:**
- Modify: `PadDeck/CLAUDE.md`

- [ ] **Step 1: Add instrument architecture documentation**

Add after the "## Project Sharing" section and before "## Build":

```markdown
## Playable Instruments

- 5 instrument types: Piano, Drums, Marimba, Synth Lead, Synth Pad
- `InstrumentEngine` manages `AVAudioUnitSampler` instances, one per instrument type
- Samplers connect to `AudioEngine.mixerNode` (exposed read-only for this purpose)
- SoundFont (.sf2) files bundled in `PadDeck/Resources/SoundFonts/`
- `InstrumentType` enum defines note layouts via `NoteLayout` (GridPosition → MIDI note mapping + LED colors)
- Instrument mode: `AppState.activeInstrument` reroutes pad press/release to `InstrumentEngine.playNote`/`stopNote`
- Side button 7 (top) exits instrument mode
- Grid layouts: Piano/Marimba = chromatic (1 octave/row), Drums = 4×4 quadrant, Synth Lead/Pad = isomorphic 4ths (+5 semitones/row)
```

Also update the "## Project Structure" to add:

```markdown
- `Models/` — ... InstrumentType, InstrumentConfig, NoteLayout
- `Managers/` — ... InstrumentEngine
```

- [ ] **Step 2: Commit**

```bash
git add PadDeck/CLAUDE.md
git commit -m "docs: add instrument architecture to CLAUDE.md"
```

---

## Verification

After all tasks are complete, verify end-to-end:

1. **Build**: `xcodebuild -project build/PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' build` succeeds without warnings
2. **Edit mode**: Launch app → toggle Edit mode → click empty pad → see "INSTRUMENT" section → click "Piano" → pad shows piano icon with blue-white color
3. **Switch instrument type**: With instrument pad selected → click "Drums" in type selector → icon and color update
4. **Play mode (app)**: Toggle to Play mode → click the instrument pad → status bar appears showing "Piano" → click Exit → returns to normal grid
5. **Play mode (Launchpad)**: Connect Launchpad → press instrument pad → grid lights up with instrument colors → press note pads to hear sounds → press side button 8 (top) to exit
6. **Drums layout**: Assign Drums instrument → enter instrument mode → verify only bottom-left 4×4 lights up with colored pads, rest dark
7. **Velocity**: Press pads at different velocities → louder/softer notes
8. **Polyphony**: Hold multiple pads simultaneously → all notes sound together
9. **Persistence**: Save project → quit app → relaunch → instrument pad configuration preserved
10. **Project switch**: Switch projects while in instrument mode → exits cleanly, loads new project
11. **Stop All**: Press Stop All while in instrument mode → exits instrument mode and stops all audio
