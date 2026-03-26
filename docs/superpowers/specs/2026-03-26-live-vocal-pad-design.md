# Live Vocal Pad Feature

## Context

The paddeck app currently plays audio samples triggered by pads on a Novation Launchpad. Users want the ability to route a live microphone through a pad with selectable vocal effects (reverb, delay, pitch shift, distortion) and dry/wet control via the Launchpad's scene buttons. This enables live vocal performance alongside sample playback.

## Requirements

- **One live vocal pad** at a time (mic-only, no sample)
- **Two activation modes**: Hold (mic on while pressed) and Select (tap to toggle)
- **Four effects**: Reverb, Delay, Pitch Shift, Distortion — one active at a time
- **Dry/wet control** via scene buttons: 2 buttons (up/down) + 6-LED bar meter
- **Global mic gain** in Settings (not per-pad)
- **XY mode removed** entirely to free scene buttons

## Data Model

### New Types

**`VocalEffect`** enum (new file `Models/VocalEffect.swift`):
- Cases: `.reverb`, `.delay`, `.pitchShift`, `.distortion`
- Conforms to `String, Codable, CaseIterable, Identifiable, Sendable`
- Has `displayName` and `iconName` computed properties

**`VocalActivationMode`** enum (new file `Models/VocalActivationMode.swift`):
- Cases: `.hold`, `.select`
- Conforms to `String, Codable, CaseIterable, Identifiable, Sendable`
- `.hold` = mic active while pad held; `.select` = tap to toggle

**`VocalPadConfig`** struct (new file `Models/VocalPadConfig.swift`):
- `effect: VocalEffect` (default: `.reverb`)
- `activationMode: VocalActivationMode` (default: `.hold`)
- `dryWetMix: Float` (0.0–1.0, default: 0.5)
- Conforms to `Codable, Sendable`

### Modified Types

**`PadConfiguration`** — add:
- `var vocalConfig: VocalPadConfig?` (nil = sample pad, non-nil = vocal pad)
- `var isVocalPad: Bool { vocalConfig != nil }`
- Update `isEmpty`: `sample == nil && vocalConfig == nil`
- Mutual exclusion enforced in `AppState.updatePad()`: setting `vocalConfig` clears `sample` (and vice versa) before saving

**`AppMode`** — remove `xyPad` case. Simplify to just `.normal` or remove the enum entirely.

### Global State

- `micGain: Float` stored in `UserDefaults` (key: `"micGain"`, default: `1.0`, range: 0.0–2.0)
- `isMicActive: Bool` tracked on `AppState` (not persisted)
- `vocalPadPosition: GridPosition?` computed from project pads

## Audio Graph Architecture

### Approach: Pre-attached Nodes, Hot-Swap Connections

```
Existing (unchanged):
  AVAudioPlayerNode → AVAudioUnitTimePitch → mixer → mainMixerNode → output

New mic chain:
  engine.inputNode → micGainNode → [activeEffect] → mixer → mainMixerNode → output

Pre-attached pool (connected only when active):
  - AVAudioUnitReverb
  - AVAudioUnitDelay
  - AVAudioUnitTimePitch (separate from per-pad instances)
  - AVAudioUnitDistortion
```

### AudioEngine Changes

**New properties:**
- `micGainNode: AVAudioMixerNode` — volume acts as gate (0 = muted)
- `reverbNode: AVAudioUnitReverb`
- `delayNode: AVAudioUnitDelay`
- `vocalPitchNode: AVAudioUnitTimePitch` (named to distinguish from per-pad pitch nodes)
- `distortionNode: AVAudioUnitDistortion`
- `activeVocalEffect: VocalEffect?`
- `globalMicGain: Float = 1.0`

**New methods:**
- `setupMicChain()` — called in `setupEngine()`. Attaches all 5 nodes. Connects default chain: `inputNode → micGainNode → reverbNode → mixer`. Sets `micGainNode.volume = 0`.
- `setMicActive(_ active: Bool)` — sets `micGainNode.volume = active ? globalMicGain : 0`
- `switchVocalEffect(to effect: VocalEffect)` — disconnects current effect from `micGainNode` and `mixer`, connects new effect. No engine pause needed since nodes are pre-attached.
- `setVocalDryWet(_ value: Float)` — sets active effect's `wetDryMix = value * 100`
- `setMicGain(_ gain: Float)` — stores `globalMicGain`, updates `micGainNode.volume` if mic is currently active

**Effect node defaults:**
- Reverb: `.largeHall2` preset, wetDryMix 50
- Delay: delayTime 0.3s, feedback 30%, lowPassCutoff 15000, wetDryMix 50
- Pitch Shift: pitch +1200 cents (+1 octave, classic vocal effect), wetDryMix 50
- Distortion: `.speechWaves` preset, wetDryMix 50

### Recording Coexistence

No changes to recording. Recording uses `inputNode.installTap()` which coexists with node connections. Recording is only for creating sample pads, not related to vocal pads.

## MIDI & LED Behavior

### Scene Buttons (Right Column, Indices 0–7)

With XY mode removed, all 8 scene buttons are repurposed:

| Index | Note | Function |
|-------|------|----------|
| 7     | 89   | Dry/wet **UP** (+20%) |
| 6     | 79   | Dry/wet **DOWN** (-20%) |
| 5     | 69   | Bar meter LED 6 (top) |
| 4     | 59   | Bar meter LED 5 |
| 3     | 49   | Bar meter LED 4 |
| 2     | 39   | Bar meter LED 3 |
| 1     | 29   | Bar meter LED 2 |
| 0     | 19   | Bar meter LED 1 (bottom) |

**Dry/wet levels** — 7 visual states (0–6 lit LEDs), mapped to dry/wet 0.0–1.0:

| LEDs lit | Value  | Dry/wet float |
|----------|--------|---------------|
| 0        | 0%     | 0.0           |
| 1        | ~17%   | 0.167         |
| 2        | ~33%   | 0.333         |
| 3        | 50%    | 0.5           |
| 4        | ~67%   | 0.667         |
| 5        | ~83%   | 0.833         |
| 6 (all)  | 100%   | 1.0           |

Up button increments by 1 LED step (1/6 ≈ 0.167), down decrements. Clamped to 0–6.

**LED colors:**
- Lit LEDs: gradient from green (index 0, dry) to blue (index 5, wet)
- Unlit LEDs: dim gray
- Up/down buttons (6, 7): white when vocal pad exists, off otherwise

**Scene buttons only active when a vocal pad exists** in the project. All off otherwise.

### Vocal Pad LED

- **Configured, mic off**: pad's configured color (default magenta `r:127 g:0 b:80`)
- **Mic active**: pulsing LED via `setLEDPulsing` (already implemented in MIDIManager)

### Side Button Handler

In `AppState.setupMIDICallbacks()`, replace the XY toggle logic:

```
onSideButtonPressed = { index in
    guard vocalPadPosition != nil else { return }
    if index == 7: increment dry/wet step, update effect + LEDs
    if index == 6: decrement dry/wet step, update effect + LEDs
}
```

No `onSideButtonReleased` needed — these are momentary press actions.

## UI Changes

### PadDetailView

**When pad has `vocalConfig` (vocal pad):**

Replace sample-specific sections with:
1. **Header**: "LIVE VOCAL" with mic icon, close button
2. **EFFECT** section: 4 buttons (Reverb/Delay/Pitch Shift/Distortion) using `PlayModeButton` pattern
3. **ACTIVATION** section: 2 buttons (Hold/Select) using `PlayModeButton` pattern
4. **DRY/WET** section: Slider 0–100%, synced with Launchpad scene buttons
5. **COLOR** section: existing `ColorPickerView`
6. **Actions**: "Remove Vocal" button (clears `vocalConfig`)

**When pad is empty:**

Add "Live Vocal" button in the empty pad area:
- Mic icon + "Live Vocal" label
- On tap: checks if another pad already has `vocalConfig`
  - If yes: move vocal config to this pad (clear old pad)
  - If no: create new `VocalPadConfig()` with defaults
- Sets default color to magenta

**When dropping a file on a vocal pad:**

Convert back to sample pad: clear `vocalConfig`, set `sample`.

### SettingsView

Add a **Microphone** section (in MIDI tab or new Audio tab):
- Mic gain slider: 0–200% (maps to 0.0–2.0 float)
- Label showing current percentage

## AppState Changes

### Remove XY Mode

- Remove `AppMode.xyPad` case
- Remove `canEnterXYMode`, `enterXYMode()`, `exitXYMode()`, `toggleXYMode()`
- Remove `handleXYPress()`, `pentatonicSemitones`, `pentatonicNoteNames`
- Remove `updateXYButtonLED()`
- Remove XY references from `handlePadPress`, `handlePadRelease`, `onPadStopped`

### Add Vocal Pad Logic

**New properties:**
- `isMicActive: Bool = false`
- `var vocalPadPosition: GridPosition?` — computed by scanning `project.pads` for one with `vocalConfig != nil`
- `micGain: Float` — backed by UserDefaults

**Modified `handlePadPress`:**
```
if pad.isVocalPad:
    if activationMode == .hold:
        audioEngine.setMicActive(true)
        isMicActive = true
        set pulsing LED
    if activationMode == .select:
        toggle isMicActive
        audioEngine.setMicActive(isMicActive)
        update LED (pulsing if active, static color if not)
    return (skip sample playback logic)
else:
    existing sample playback logic (unchanged)
```

**Modified `handlePadRelease`:**
```
if pad.isVocalPad && pad.vocalConfig?.activationMode == .hold:
    audioEngine.setMicActive(false)
    isMicActive = false
    set static LED color
    return
else:
    existing release logic (unchanged)
```

**Scene button dry/wet rendering:**
- `renderDryWetMeter()` — updates 6 bar LEDs + 2 control button LEDs
- Called after dry/wet changes and on device connect

## Verification

1. **Build**: `xcodegen generate && xcodebuild -scheme PadDeck -configuration Debug build`
2. **Assign vocal pad**: Click empty pad → "Live Vocal" button → verify pad shows vocal config UI
3. **Mic audio**: With headphones, activate vocal pad → verify mic audio passes through speakers
4. **Effects**: Switch between reverb/delay/pitch/distortion → verify audible difference
5. **Hold mode**: Hold pad on Launchpad → mic active; release → mic stops
6. **Select mode**: Tap pad → mic toggles on; tap again → off
7. **Dry/wet**: Press scene button 7 (up) → dry/wet increases, bar meter updates; press 6 (down) → decreases
8. **LED feedback**: Vocal pad pulses when active, static when inactive; scene buttons show bar meter
9. **Persistence**: Save project, reload → vocal pad config preserved
10. **One-at-a-time**: Assign vocal to pad A, then assign to pad B → pad A reverts to empty
11. **Recording**: Recording still works independently (creates sample pads)
12. **Drop file on vocal pad**: Converts to sample pad
