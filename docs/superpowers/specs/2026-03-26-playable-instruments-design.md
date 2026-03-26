# Playable Instruments on the Launchpad

**Date**: 2026-03-26
**Status**: Draft

## Overview

Add 5 playable instruments to PadDeck so that any pad can be configured as an instrument trigger. In play mode, tapping an instrument pad transforms the entire 8×8 Launchpad grid into a playable note layout for that instrument. Each instrument type has its own grid layout optimized for its playing style, powered by AVAudioUnitSampler with bundled SoundFont (.sf2) files.

### Instruments

| Instrument | Grid Layout | Note Range | Character |
|-----------|-------------|------------|-----------|
| Piano | Chromatic (1 octave/row) | C1–C8 (MIDI 24–108) | Acoustic piano |
| Drums | 4×4 quadrant (bottom-left) | GM drum map (MIDI 35–75) | Standard kit |
| Marimba | Chromatic (1 octave/row) | F2–C9 (MIDI 41–127) | Warm marimba |
| Synth Lead | Isomorphic 4ths (+5/row) | C3 base (MIDI 48) | Soft, playable lead |
| Synth Pad | Isomorphic 4ths (+5/row) | C2 base (MIDI 36) | Warm, lush pad |

## Data Model

### New Types

#### `InstrumentType` enum

```
PadDeck/Models/InstrumentType.swift
```

```swift
enum InstrumentType: String, Codable, CaseIterable, Sendable {
    case piano
    case drums
    case marimba
    case synthLead
    case synthPad
}
```

Properties via extension:
- `displayName: String` — "Piano", "Drums", "Marimba", "Synth Lead", "Synth Pad"
- `iconName: String` — SF Symbols: "pianokeys", "drum.fill", "music.quarternote.3", "waveform", "waveform.path"
- `soundFontFilename: String` — "Piano.sf2", "Drums.sf2", etc.
- `defaultColor: LaunchpadColor` — signature color per instrument
- `noteLayout: NoteLayout` — grid-to-MIDI-note mapping (see below)

Conforms to `EffectOption` protocol (already exists in PadDetailView) for reuse in the instrument type selector UI.

#### `InstrumentConfig` struct

```
PadDeck/Models/InstrumentConfig.swift
```

```swift
struct InstrumentConfig: Codable, Sendable {
    var instrumentType: InstrumentType
    var volume: Float  // 0-1, default 0.8

    init(instrumentType: InstrumentType, volume: Float = 0.8) {
        self.instrumentType = instrumentType
        self.volume = volume
    }
}
```

#### `NoteLayout` struct

```
PadDeck/Models/NoteLayout.swift
```

Defines the mapping from GridPosition to MIDI note number for a given instrument, plus LED colors:

```swift
struct NoteLayout {
    /// Returns the MIDI note for a grid position, or nil if the pad is inactive.
    let noteForPosition: (GridPosition) -> UInt8?

    /// Returns the LED color for a grid position (rest state).
    let colorForPosition: (GridPosition) -> LaunchpadColor

    /// Color to show when a pad is pressed.
    let pressedColor: LaunchpadColor
}
```

Note naming convention: **C4 = MIDI 60 (Middle C)**. This matches Ableton Live and most modern DAWs.

Static factory methods on `InstrumentType`:
- `InstrumentType.piano` → chromatic layout starting at MIDI 24 (C1), row 0 col 0 = C1, each column +1 semitone, each row +1 octave (+12 semitones)
- `InstrumentType.drums` → 4×4 bottom-left quadrant (rows 0-3, cols 0-3) mapped to GM drum notes, remaining pads return nil
- `InstrumentType.marimba` → chromatic starting at MIDI 53 (F2), each row +1 octave
- `InstrumentType.synthLead` → isomorphic 4ths starting at MIDI 48 (C3), each row +5 semitones
- `InstrumentType.synthPad` → isomorphic 4ths starting at MIDI 36 (C2), each row +5 semitones

### Modified Types

#### `PadConfiguration` (modified)

```
PadDeck/Models/PadConfiguration.swift
```

Add:
```swift
var instrumentConfig: InstrumentConfig?
var isInstrumentPad: Bool { instrumentConfig != nil }
```

Update:
```swift
var isEmpty: Bool { sample == nil && vocalConfig == nil && instrumentConfig == nil }
```

Add parameter to full initializer:
```swift
init(position:sample:color:playMode:volume:emoji:vocalConfig:instrumentConfig:)
```

## InstrumentEngine

```
PadDeck/Managers/InstrumentEngine.swift
```

New `@Observable final class` manager that owns `AVAudioUnitSampler` instances.

### Responsibilities

1. **Sampler lifecycle**: Lazy-create one `AVAudioUnitSampler` per `InstrumentType`, attach to AudioEngine's mixer
2. **SoundFont loading**: Load bundled `.sf2` files, select appropriate program/bank
3. **Note playback**: `playNote(note:velocity:instrument:)` and `stopNote(note:instrument:)`
4. **Cleanup**: `stopAllNotes()` when exiting instrument mode

### Audio Graph Integration

`AudioEngine` exposes its internal `mixer` node via a new read-only property:

```swift
// AudioEngine.swift
var mixerNode: AVAudioMixerNode { mixer }
var audioEngine: AVAudioEngine { engine }
```

`InstrumentEngine` attaches sampler nodes to this mixer:

```swift
func loadInstrument(_ type: InstrumentType) {
    guard samplers[type] == nil else { return }
    let sampler = AVAudioUnitSampler()
    audioEngine.audioEngine.attach(sampler)
    audioEngine.audioEngine.connect(sampler, to: audioEngine.mixerNode, format: nil)
    // Load .sf2 from bundle
    let url = Bundle.main.url(forResource: type.soundFontFilename, withExtension: nil)!
    try? sampler.loadSoundBankInstrument(at: url, program: 0, bankMSB: 0x79, bankLSB: 0)
    samplers[type] = sampler
}
```

For drums, use `bankMSB: 0x78` (GM percussion bank) and program 0.

### Note Playback

```swift
func playNote(note: UInt8, velocity: UInt8, instrument: InstrumentType) {
    guard let sampler = samplers[instrument] else { return }
    // For drums, use MIDI channel 10 (index 9)
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
```

## Instrument Mode (AppState)

### New State

```swift
// AppState.swift
struct ActiveInstrument {
    let type: InstrumentType
    let sourcePosition: GridPosition
}

var activeInstrument: ActiveInstrument?
let instrumentEngine: InstrumentEngine
```

`activeInstrument` is non-nil when the grid is in instrument mode. `sourcePosition` tracks which pad triggered the mode (for LED restoration on exit). `ActiveInstrument` is a struct (not a tuple) for clean `@Observable` integration.

### Entering Instrument Mode

In `handlePadPress`, before the existing sample/vocal logic:

```swift
// If pad is an instrument pad, enter instrument mode
if pad.isInstrumentPad, let config = pad.instrumentConfig {
    activeInstrument = ActiveInstrument(type: config.instrumentType, sourcePosition: position)
    instrumentEngine.loadInstrument(config.instrumentType)
    renderInstrumentGrid(config.instrumentType)
    return
}
```

### Playing Notes in Instrument Mode

When `activeInstrument` is set, `handlePadPress` routes to instrument playback instead of sample playback:

```swift
if let active = activeInstrument {
    let layout = active.type.noteLayout
    guard let note = layout.noteForPosition(position) else { return }
    instrumentEngine.playNote(note: note, velocity: velocity, instrument: active.type)
    midiManager.setLED(at: position, color: layout.pressedColor)
    return
}
```

Similarly, `handlePadRelease` sends note-off:

```swift
if let active = activeInstrument {
    let layout = active.type.noteLayout
    guard let note = layout.noteForPosition(position) else { return }
    instrumentEngine.stopNote(note: note, instrument: active.type)
    midiManager.setLED(at: position, color: layout.colorForPosition(position))
    return
}
```

### Exiting Instrument Mode

Via side button 8 (top) or on-screen exit button:

```swift
func exitInstrumentMode() {
    instrumentEngine.stopAllNotes()
    activeInstrument = nil
    midiManager.syncLEDs(with: project, playingPads: audioEngine.activePads)
    renderDryWetMeter()
}
```

### Side Button Handling

When in instrument mode, side buttons are repurposed:

```swift
midiManager.onSideButtonPressed = { [weak self] index in
    guard let self else { return }
    if self.activeInstrument != nil {
        if index == 7 { // Top button = exit
            self.exitInstrumentMode()
        }
        return  // Swallow other side buttons in instrument mode
    }
    // Existing dry/wet handling...
}
```

### LED Rendering

```swift
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

    // Side buttons: only top button lit (exit)
    for i in 0..<7 {
        midiManager.setSideButtonLED(index: i, color: .off)
    }
    midiManager.setSideButtonLED(index: 7, color: LaunchpadColor(r: 127, g: 20, b: 20))
}
```

## Grid Layouts (Detail)

### Piano — Chromatic

Each row = one octave (12 semitones offset from the row below). Row 0 starts at C1 (MIDI 24). 8 pads per row = 8 consecutive semitones (C through G of each octave).

Note: Uses C4 = MIDI 60 convention (Middle C).

```
Row 7: C8  C#8 D8  D#8 E8  F8  F#8 G8     (MIDI 108-115, clamped to 108)
Row 6: C7  C#7 D7  D#7 E7  F7  F#7 G7     (MIDI 96-103)
Row 5: C6  C#6 D6  D#6 E6  F6  F#6 G6     (MIDI 84-91)
Row 4: C5  C#5 D5  D#5 E5  F5  F#5 G5     (MIDI 72-79)
Row 3: C4  C#4 D4  D#4 E4  F4  F#4 G4     (MIDI 60-67)  ← Middle C row
Row 2: C3  C#3 D3  D#3 E3  F3  F#3 G3     (MIDI 48-55)
Row 1: C2  C#2 D2  D#2 E2  F2  F#2 G2     (MIDI 36-43)
Row 0: C1  C#1 D1  D#1 E1  F1  F#1 G1     (MIDI 24-31)
```

Formula: `midiNote = 24 + (row * 12) + column`

MIDI notes above 108 (C8) should be clamped to 108 or return nil.

**LED colors**: White keys (C,D,E,F,G,A,B) = white `(100,100,100)`, Black keys (C#,D#,F#,G#,A#) = dim blue `(15,15,60)`.

Determining white vs black: `note % 12` in `{1, 3, 6, 8, 10}` = black key.

### Drums — 4×4 Quadrant

Bottom-left 4×4 (rows 0-3, cols 0-3):

```
Row 4: [Crash]49 [Ride]51  [OpenHH]46  [ClosedHH]42
Row 3: [HiTom]50 [MidTom]47 [LowTom]45 [Cowbell]56
Row 2: [Snare]38 [Clap]39  [Rimshot]37 [Clave]75
Row 1: [Kick]36  [Kick2]35 [SideStk]40 [FloorTom]43
```

Remaining pads (cols 4-7, rows 4-7) return nil and are lit dark/off.

**LED colors by group**:
- Kicks: red `(127,20,0)`
- Snares: orange `(127,60,0)`
- Hi-hats: yellow `(127,127,0)`
- Cymbals: cyan `(0,127,127)`
- Toms: green `(0,127,20)`
- Percussion: purple `(80,0,127)`

### Marimba — Chromatic

Same layout structure as piano but starting at F2 (MIDI 41):

```
Row 7: ... (MIDI 125-127+, clamped to 127)
...
Row 0: F2  F#2 G2  G#2 A2  A#2 B2  C3   (MIDI 41-48)
```

Formula: `midiNote = 41 + (row * 12) + column`

**LED colors**: Naturals = warm amber `(127,70,10)`, Accidentals = dim brown `(50,25,5)`.

### Synth Lead — Isomorphic 4ths

Each row offset by 5 semitones (a perfect 4th):

```
Row 7: base + 35..42  (7×5 + 0..7)
Row 6: base + 30..37  (6×5 + 0..7)
...
Row 0: base + 0..7    (0×5 + 0..7)
```

Formula: `midiNote = base + (row * 5) + column`

Base = C3 (MIDI 48). So row 0 = 48-55, row 1 = 53-60, etc.

**LED colors**: Notes where `column == 0` (leftmost, root of each row) = bright green `(0,127,30)`, others = dim green `(0,40,10)`.

### Synth Pad — Isomorphic 4ths

Identical layout to Synth Lead but base = C2 (MIDI 36).

Formula: `midiNote = 36 + (row * 5) + column`

**LED colors**: `column == 0` = bright purple `(100,0,127)`, others = dim purple `(30,0,50)`.

## UI Changes

### GridView — Instrument Mode Overlay

When `appState.activeInstrument != nil`, show a floating status bar at the top of GridView:

```swift
// Inside GridView body, overlay on VStack
.overlay(alignment: .top) {
    if let active = appState.activeInstrument {
        InstrumentStatusBar(
            instrumentType: active.type,
            onExit: { appState.exitInstrumentMode() }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
```

`InstrumentStatusBar` is a small view:
```
┌─────────────────────────────────────────┐
│  🎹 Piano                    [× Exit]  │
└─────────────────────────────────────────┘
```

Styled with the instrument's accent color, semi-transparent background, rounded corners.

### PadDetailView — Instrument Assignment

In the empty pad section (alongside "Live Vocal" and "Factory Samples"), add an "INSTRUMENT" section:

```swift
DetailSection(title: "INSTRUMENT", icon: "pianokeys") {
    VStack(spacing: 6) {
        ForEach(InstrumentType.allCases, id: \.self) { type in
            InstrumentAssignButton(type: type) {
                assignInstrumentPad(type)
            }
        }
    }
}
```

Each button shows icon, name, and a brief description. Tapping assigns the pad as that instrument type.

### PadDetailView — Instrument Pad Editor

When `pad.isInstrumentPad`, show:
1. Header with instrument icon and name
2. Instrument type selector (switch between the 5 types)
3. Volume slider
4. Color picker
5. "Remove Instrument" button

Pattern matches the existing vocal pad editor.

### PadView — Instrument Indicator

When a pad has an instrument config, show the instrument's SF Symbol icon (similar to how vocal pads show a mic icon). Use the instrument's accent color.

## SoundFont Assets

Bundle in `PadDeck/Resources/SoundFonts/`:

| File | Instrument | Approx Size | Source |
|------|-----------|-------------|--------|
| Piano.sf2 | Acoustic Grand Piano | ~2-3 MB | Open-source GM SoundFont |
| Drums.sf2 | Standard Drum Kit | ~1-2 MB | Open-source GM SoundFont |
| Marimba.sf2 | Marimba | ~1 MB | Open-source GM SoundFont |
| SynthLead.sf2 | Soft Synth Lead | ~500 KB | Open-source GM SoundFont |
| SynthPad.sf2 | Warm Pad | ~500 KB | Open-source GM SoundFont |

Added to project.yml as bundle resources. Total ~5-7 MB.

Alternative: Use a single General MIDI SoundFont (~5-10 MB) and select different programs. This simplifies asset management but limits sound customization per instrument.

## Project Serialization

`InstrumentConfig` is `Codable` — serializes naturally with `PadConfiguration`. No migration needed since `instrumentConfig` is optional (nil by default). Existing projects load without change.

Bundle export/import (`PadDeckBundle`) requires no changes — instrument pads have no external audio files to bundle.

## Files to Create

| File | Type |
|------|------|
| `PadDeck/Models/InstrumentType.swift` | Model + NoteLayout |
| `PadDeck/Models/InstrumentConfig.swift` | Model |
| `PadDeck/Models/NoteLayout.swift` | Model |
| `PadDeck/Managers/InstrumentEngine.swift` | Manager |
| `PadDeck/Views/Grid/InstrumentStatusBar.swift` | View |
| `PadDeck/Resources/SoundFonts/*.sf2` | Assets (5 files) |

## Files to Modify

| File | Changes |
|------|---------|
| `PadDeck/Models/PadConfiguration.swift` | Add `instrumentConfig` property |
| `PadDeck/App/AppState.swift` | Add `activeInstrument`, `instrumentEngine`, instrument mode routing in pad press/release, side button handling, `exitInstrumentMode()`, `renderInstrumentGrid()` |
| `PadDeck/Managers/AudioEngine.swift` | Expose `mixerNode` and `audioEngine` as read-only |
| `PadDeck/Views/Grid/GridView.swift` | Add instrument status bar overlay |
| `PadDeck/Views/Grid/PadView.swift` | Show instrument icon for instrument pads |
| `PadDeck/Views/PadDetail/PadDetailView.swift` | Add instrument assignment section (empty pad), instrument editor (instrument pad) |
| `PadDeck/CLAUDE.md` | Document instrument architecture |

## Verification

1. **Build**: Project compiles without warnings on macOS and iPadOS targets
2. **Edit mode**: Select empty pad → see "Instrument" section → assign Piano → pad shows piano icon and color
3. **Play mode (app only)**: Click instrument pad → grid overlay shows "Piano" status bar → click exit → returns to normal
4. **Play mode (Launchpad)**: Press instrument pad → Launchpad lights up with piano layout → press pads to hear notes → press side button 8 to exit
5. **Drums layout**: Verify 4×4 quadrant lights up, remaining pads dark, each drum pad triggers correct GM sound
6. **Isomorphic layout**: Verify synth lead/pad rows are offset by 5 semitones
7. **Persistence**: Save project with instrument pad → reload → instrument config preserved
8. **Velocity**: Notes respond to MIDI velocity (louder with harder press)
9. **Polyphony**: Multiple notes can sound simultaneously
10. **Project switch**: Switching projects exits instrument mode cleanly
