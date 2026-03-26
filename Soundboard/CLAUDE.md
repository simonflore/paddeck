# Soundboard

macOS 14+ SwiftUI app for controlling Novation Launchpad controllers as a soundboard.
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

- `App/` — SoundboardApp entry point, AppState
- `Managers/` — MIDIManager, AudioEngine, SampleStore, ProjectManager, TextScroller
- `Models/` — GridPosition, PadConfiguration, Project, Sample, LaunchpadColor, LaunchpadModel, PlayMode
- `Views/Grid/` — ContentView, GridView, PadView
- `Views/PadDetail/` — PadDetailView, ColorPickerView, WaveformTrimView
- `Utilities/` — LaunchpadProtocol, PixelFont, AudioFormats, PressureTracker

## Build

- XcodeGen project (`project.yml`), Swift 5.9, macOS 14.0 deployment target
- External dependency: DSWaveformImage v14.0.0+
