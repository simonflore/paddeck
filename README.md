# Soundboard

A macOS app for turning a **Novation Launchpad X** into a fully customizable soundboard. Assign audio samples to pads, control RGB LEDs, trim waveforms, and perform live with an XY pitch/speed controller.

## Features

- **8x8 Pad Grid** — drag-and-drop audio files onto pads, rearrange by dragging between pads
- **Launchpad X Integration** — real-time LED color sync, programmer mode SysEx, velocity-sensitive playback via Force Touch
- **Audio Engine** — AVAudioEngine-based playback with per-pad volume, one-shot / loop / hold play modes
- **Waveform Trimming** — visual trim editor with start/end handles
- **XY Performance Mode** — 2D pad controller for live pitch and speed manipulation
- **Recording** — record audio directly from your microphone and assign to pads
- **Project Management** — save and load soundboard configurations
- **LED Text Scroller** — scrolls sample names across the Launchpad grid on playback
- **Factory Presets** — 6 built-in synth samples (sine, pad, pluck, sub bass, lead, bell)

## Requirements

- macOS 14.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Novation Launchpad X (optional — the app works without hardware)

## Build

```bash
# Generate Xcode project
xcodegen generate

# Open in Xcode
open Soundboard.xcodeproj

# Or build from command line
xcodebuild -project Soundboard.xcodeproj -scheme Soundboard -configuration Debug build
```

## Architecture

```
App/            — SoundboardApp entry point, AppState (root coordinator)
Models/         — Value-type structs: Project, PadConfiguration, Sample, GridPosition, etc.
Managers/       — @Observable managers: MIDIManager, AudioEngine, SampleStore, ProjectManager
Views/Grid/     — Main 8x8 grid UI with drag-drop support
Views/PadDetail/— Pad editor: waveform trimmer, color picker, emoji selector
Views/Settings/ — MIDI device and project management
Views/Recording/— Audio recording dialog
Utilities/      — Launchpad SysEx protocol, MIDI mapping, pixel font, audio formats
```

`AppState` coordinates all managers via closure callbacks. Models are `Codable` and `Sendable` value types. Grid positions map to MIDI notes: `(row + 1) * 10 + (col + 1)` (Launchpad X programmer mode).

## Dependencies

- [DSWaveformImage](https://github.com/dmrschmidt/DSWaveformImage) — waveform rendering for the trim editor

## License

[MIT](LICENSE)
