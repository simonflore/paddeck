# PadDeck

Multiplatform (macOS 14+ / iPadOS 17+) SwiftUI app for controlling Novation Launchpad controllers as a live performance audio deck.
Supports: Launchpad X, Mini MK3, Pro MK3, MK2, and Pro (original).

## Architecture

- `AppState` is the root `@Observable` coordinating all managers via closure callbacks
- Managers are `@Observable final class`: MIDIManager, AudioEngine, SampleStore, ProjectManager, TextScroller
- Models are value-type structs (`Codable, Sendable`): Project, PadConfiguration, GridPosition, Sample
- `PadConfiguration.position` is `let` — grid positions are fixed (mapped to MIDI notes). "Moving" a pad means swapping contents.
- Grid positions map to MIDI notes: `(row+1)*10 + (col+1)` (programmer mode, all supported models)

## MIDI

- `MIDISendSysex` is async — the `MIDISysexSendRequest` struct MUST be heap-allocated and freed in the completion proc
- CoreMIDI advances `request.data` pointer during send — save original base address in `completionRefCon` for deallocation
- LED updates: `setLED` (single), `syncLEDs` (full grid), `sendBatchLEDs` (batch SysEx)
- MIDI callbacks run on background threads — always dispatch to main queue
- `LaunchpadModel` enum defines per-model constants (device ID, SysEx payloads, protocol variant)
- `LaunchpadProtocol` struct (initialized with a model) builds SysEx messages — modern (X, Mini MK3, Pro MK3) uses 0x03 RGB format, intermediate (MK2, Pro) uses 0x0B
- `MIDIManager` auto-detects the model from MIDI endpoint name on connection
- Side buttons are normalized to logical indices (0-7) so AppState doesn't depend on raw MIDI notes

## Project Structure

- `App/` — PadDeckApp entry point, AppState
- `Managers/` — MIDIManager, AudioEngine, InstrumentEngine, SampleStore, ProjectManager, TextScroller
- `Models/` — GridPosition, PadConfiguration, Project, Sample, LaunchpadColor, LaunchpadModel, PlayMode, InstrumentType, InstrumentConfig, NoteLayout
- `Views/Grid/` — ContentView, GridView, PadView
- `Views/PadDetail/` — PadDetailView, ColorPickerView, WaveformTrimView
- `Utilities/` — LaunchpadProtocol, PixelFont, AudioFormats, PressureTracker

## Multiplatform

- Single target with `supportedDestinations: [macOS, iOS]` — no code duplication
- Platform-specific code is isolated behind `#if os(macOS)` / `#if os(iOS)` in ~5 files
- macOS: AppKit mouse handler (PadMouseNSView), Force Touch pressure (PressureTracker), NSAppearance, HSplitView, Settings scene
- iOS: UIKit touch handler (PadTouchUIView), AVAudioSession setup, HStack layout, settings via sheet, `.draggable()` for pad reorder
- CoreMIDI works on both platforms (iPad connects via USB-C)
- AudioEngine, MIDIManager, SampleStore, ProjectManager, all Models — fully shared

## Project Sharing

- `.paddeck` files are ZIP bundles containing `project.json` + `audio/` directory
- UTType `com.paddeck.project` registered for native file association on both platforms
- `PadDeckBundle` handles export (ZIP creation) and import (unzip + file copy)
- Import with name collision offers "Replace" or "Keep Both"
- ZIPFoundation dependency for cross-platform ZIP handling

## Playable Instruments

- 5 instrument types: Piano, Drums, Marimba, Synth Lead, Synth Pad
- `InstrumentEngine` manages `AVAudioUnitSampler` instances, one per instrument type
- Samplers connect to `AudioEngine.mixerNode` (exposed read-only for this purpose)
- SoundFont (.sf2) files bundled in `PadDeck/Resources/SoundFonts/`
- `InstrumentType` enum defines note layouts via `NoteLayout` (GridPosition → MIDI note mapping + LED colors)
- Instrument mode: `AppState.activeInstrument` reroutes pad press/release to `InstrumentEngine.playNote`/`stopNote`
- Side button 7 (top) exits instrument mode
- Grid layouts: All melodic instruments use isomorphic patterns — Piano = 4ths (+5/row, C2), Marimba = 3rds (+4/row, C3), Synth Lead = 4ths (+5/row, C3), Synth Pad = 5ths (+7/row, C2). Drums = full 8×8 GM percussion grid (rows 0-5 active, 6-7 off)

## Build

- XcodeGen project (`project.yml`), Swift 5.9
- macOS 14.0 / iPadOS 17.0 deployment targets
- External dependencies: DSWaveformImage v14.0.0+, ZIPFoundation v0.9.0+
