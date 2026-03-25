# Soundboard

macOS 14+ SwiftUI app for controlling a Novation Launchpad X as a soundboard.

## Architecture

- `AppState` is the root `@Observable` coordinating all managers via closure callbacks
- Managers are `@Observable final class`: MIDIManager, AudioEngine, SampleStore, ProjectManager, TextScroller
- Models are value-type structs (`Codable, Sendable`): Project, PadConfiguration, GridPosition, Sample
- `PadConfiguration.position` is `let` — grid positions are fixed (mapped to MIDI notes). "Moving" a pad means swapping contents.
- Grid positions map to MIDI notes: `(row+1)*10 + (col+1)` (Launchpad X programmer mode)

## MIDI

- `MIDISendSysex` is async — the `MIDISysexSendRequest` struct MUST be heap-allocated and freed in the completion proc
- CoreMIDI advances `request.data` pointer during send — save original base address in `completionRefCon` for deallocation
- LED updates: `setLED` (single), `syncLEDs` (full grid), `sendBatchLEDs` (batch SysEx)
- MIDI callbacks run on background threads — always dispatch to main queue
- SysEx messages built via `LaunchpadProtocol` utility (programmer mode, RGB LED, palette LED, batch RGB)

## Project Structure

- `App/` — SoundboardApp entry point, AppState
- `Managers/` — MIDIManager, AudioEngine, SampleStore, ProjectManager, TextScroller
- `Models/` — GridPosition, PadConfiguration, Project, Sample, LaunchpadColor, PlayMode
- `Views/Grid/` — ContentView, GridView, PadView
- `Views/PadDetail/` — PadDetailView, ColorPickerView, WaveformTrimView
- `Utilities/` — LaunchpadProtocol, MIDINoteMapping, PixelFont, AudioFormats, PressureTracker

## Build

- XcodeGen project (`project.yml`), Swift 5.9, macOS 14.0 deployment target
- External dependency: DSWaveformImage v14.0.0+
