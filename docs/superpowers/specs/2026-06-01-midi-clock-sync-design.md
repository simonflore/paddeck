# External MIDI Clock Sync for PadDeck

## Problem

PadDeck plays looped pads the instant a pad is pressed, at the file's native
rate. Loops therefore drift out of phase with the rest of a rig. We want PadDeck
to follow an external MIDI clock (Gigmeister, a DAW, any clock master) so that
synced loops launch and loop on musical boundaries and stay tempo-locked across
many bars.

## Goals

1. Receive MIDI real-time + transport messages from a user-selectable CoreMIDI
   input, independent of the Launchpad port: Clock `0xF8`, Start `0xFA`,
   Continue `0xFB`, Stop `0xFC`, Song Position Pointer `0xF2`.
2. Derive a stable tempo and a bar/beat/tick transport position from the clock.
3. Quantized ("launch quantization") start/stop of synced loop pads on musical
   boundaries, with a global quantize setting and optional per-pad override.
4. Phase-locked looping so synced loops stay on the beat across many bars
   (Phase 1: fixed-tempo, boundary-aligned `.loops`).
5. Clock-follow with graceful fallback to internal/free-run when the clock
   disappears, and automatic re-lock when it returns.

Phase 2 (time-stretch to lock any tempo) is **scaffolded behind a per-pad
toggle, not implemented**.

## Decisions (from brainstorming)

- **One spec, phased build.** This document covers all of Phase 1; Phase 2 is
  scaffolded.
- **Dedicated `PadSyncConfig?`** on `PadConfiguration`, mirroring the existing
  `vocalConfig` / `instrumentConfig` optional-sub-config pattern.
- **Free-run when internal.** A synced pad pressed while *not* locked to an
  external clock plays immediately as a plain loop (existing path). No internal
  tick generator / quantize grid runs without an external clock.
- **Add unit tests** for the pure clock math (tempo, position, boundary).

## Architecture overview

Follows the existing manager + closure-callback architecture (managers are
`@Observable final class`; coordination flows through `AppState`).

```
ClockReceiver (CoreMIDI adapter, own input port)
   │  (MIDI thread: timestamp + status only)
   ▼
TransportClock (@Observable: tempo/position/boundary math + lock state)
   │  onStatusChanged / onBeat / onBoundaryCrossed (main thread, gated)
   ▼
AppState (coordinator)  ──►  SyncScheduler  ──►  AudioEngine (sample-accurate)
   │                                          (scheduleBuffer(at:))
   └──►  MIDIManager (LED blink/pulse)
```

### New files

| File | Responsibility |
|---|---|
| `Models/MusicalTime.swift` | `TimeSignature`, `Quantization`, `MusicalPosition`, `MusicalLength` — pure value types (`Codable, Sendable`) |
| `Models/PadSyncConfig.swift` | per-pad sync settings (`Codable, Sendable`) |
| `Models/TransportSettings.swift` | app-global transport/clock settings (`Codable, Sendable`) |
| `Managers/ClockReceiver.swift` | CoreMIDI input adapter for the clock source |
| `Managers/TransportClock.swift` | transport state + tempo/position/boundary math |
| `Managers/SyncScheduler.swift` | queue launches/stops, boundary→sample-time, drive AudioEngine, notify AppState for LEDs |
| `Views/Transport/TransportBarView.swift` | perf-facing tempo / Synced-Internal / quantize selector |
| `PadDeckTests/...` | pure clock-math unit tests |

### Modified files

| File | Change |
|---|---|
| `Models/PadConfiguration.swift` | add `var syncConfig: PadSyncConfig?` |
| `Models/Project.swift` | carry `syncConfig` through `swapPads` (also fix pre-existing dropped `instrumentConfig`) |
| `Managers/AudioEngine.swift` | sample-accurate synced-loop scheduling + latency accessor |
| `App/AppState.swift` | own `clockReceiver`/`transport`/`syncScheduler`; route synced pad press/release; LED blink/pulse |
| `Views/PadDetail/PadDetailView.swift` | Sync toggle, quantize override, loop-length, Phase-2 toggle, length-mismatch warning |
| `Views/Settings/SettingsView.swift` | clock-input picker + follow / ignore-Start-Stop / latency-offset (MIDI tab) |
| `project.yml` | add `PadDeckTests` test target |

## Data model

### `PadConfiguration`

```swift
var syncConfig: PadSyncConfig?
```

Presence ⇒ the pad is a **Synced loop**; absence ⇒ unchanged free behavior.
`playMode` remains `.loop` underneath. `Project`'s decoder is already tolerant
of missing fields, so existing projects decode with `syncConfig == nil`
(backward compatible). Update the second `init` and `swapPads` to carry
`syncConfig` (and `instrumentConfig`, which `swapPads` currently drops).

### `PadSyncConfig`

```swift
struct PadSyncConfig: Codable, Sendable, Equatable {
    var loopLength: MusicalLength          // declared length, e.g. 1 bar
    var quantizeOverride: Quantization?    // nil ⇒ use global
    var timeStretchEnabled: Bool = false   // Phase 2 scaffold, inert in Phase 1
}
```

### `MusicalTime.swift`

```swift
struct TimeSignature: Codable, Sendable, Equatable {  // default 4/4
    var beatsPerBar: Int = 4
    var beatUnit: Int = 4
}

enum Quantization: String, Codable, CaseIterable, Sendable, Identifiable {
    case sixteenth, quarter, half, bar, twoBars
    var ticks: Int { /* 6, 24, 48, 96(×ts), 192(×ts) — bar/2-bar scale with TS */ }
}

struct MusicalPosition: Equatable { var bar: Int; var beat: Int; var tick: Int }
struct MusicalLength: Codable, Sendable, Equatable { var bars: Int; var beats: Int }
```

All ticks are in 24-PPQN units (one quarter = 24 ticks). Bar/2-bar quantization
and bar→tick conversions use the active `TimeSignature`.

### `TransportSettings.swift` (app-global, UserDefaults JSON)

```swift
struct TransportSettings: Codable, Sendable {
    var globalQuantize: Quantization = .bar
    var timeSignature: TimeSignature = .init()
    var followExternalClock: Bool = true
    var ignoreStartStop: Bool = false      // for hosts that spam Start/Stop
    var latencyOffsetMs: Double = 0        // manual fine-tune (+/-)
    var manualBPM: Double = 120            // readout / last-known seed
    var clockSourceName: String?           // persisted by endpoint name
}
```

Owned by `AppState`, persisted via `UserDefaults` (JSON) with computed-property
accessors, mirroring the existing `micGain` / `duckExternalAudio` pattern.

## MIDI clock receive path (`ClockReceiver`)

`ClockReceiver` owns its **own** CoreMIDI client/input port, created with
`MIDIInputPortCreateWithProtocol(._1_0)` so CoreMIDI auto-converts legacy clock
bytes to UMP. It enumerates **all** MIDI sources (not just Launchpads) for the
picker, connects to the user-selected source by name, and re-resolves on
`msgSetupChanged` (mirrors the Launchpad auto-reconnect). Because it uses a
separate input port, the clock source may be the **same** physical endpoint as
the Launchpad or a different one — CoreMIDI permits multiple connections.

Clock/transport arrive as **UMP message type `0x1`** (System Real-Time /
Common), which `MIDIManager`'s parser ignores today. On the MIDI thread,
`ClockReceiver` does the bare minimum and forwards to `TransportClock`:

| Status | Action (MIDI thread) |
|---|---|
| `0xF8` Clock | forward packet `timeStamp` (mach host-time) + bump tick |
| `0xFA` Start | reset position to 0, running (honor `ignoreStartStop`) |
| `0xFB` Continue | running |
| `0xFC` Stop | halt (honor `ignoreStartStop`) |
| `0xF2` SPP | set tick count = `beats × 6` (1 SPP unit = 1/16 = 6 ticks) |

Other real-time bytes (`0xFE` Active Sensing, etc.) are ignored. Using the
**packet timestamp** (not main-thread arrival time) is what makes tempo
measurement jitter-free. No smoothing / UI / scheduling happens on this thread.

## Transport & tempo math (`TransportClock`)

`@Observable final class` holding `bpm`, `isLocked`, `position`, fed by the
clock callbacks. The math is factored into pure functions/value types so it can
be unit-tested without CoreMIDI:

- **Tempo:** smoothed from inter-tick host-time deltas — moving average over
  ~24 ticks (one quarter) plus a slew limit, so the displayed BPM is stable.
  `BPM = 60 / (secPerTick × 24)`. Raw ticks never drive scheduling directly.
- **Position:** tick count → `MusicalPosition` via `TimeSignature` (default
  4/4). Reset on `Start`, resume on `Continue`, set from SPP.
- **Lock state:** no `0xF8` for ~500 ms ⇒ `.internal`; ticks resume ⇒
  `.synced` (auto re-lock). A lightweight dropout check (timer or
  last-tick-time comparison) flips the state and fires `onStatusChanged`.
- **Boundary calc:** `nextBoundary(after tickCount:, quantize:) -> (tick, hostTime)`
  predicts the next boundary's tick and its host-time from the current smoothed
  tempo. Pure; shared by `SyncScheduler` and the tests.

Callbacks (main thread, gated to avoid needless hops):
- `onStatusChanged` — Synced ↔ Internal, bpm change (throttled for UI).
- `onBeat` — fired **only while synced pads are active** (for beat-pulse LEDs).
- `onBoundaryCrossed` — fired **only while launches/stops are queued** (so
  `SyncScheduler`/`AppState` can flip queued→playing LED state at the boundary).

## Quantized launch, phase-lock & latency (`SyncScheduler` + `AudioEngine`)

When a synced pad is pressed **and `transport.isLocked`**, `AppState` calls
`SyncScheduler.queueLaunch(pad)` instead of `audioEngine.play(pad:)`.

`SyncScheduler`:

1. Asks `TransportClock` for the next boundary host-time using the pad's
   `quantizeOverride ?? globalQuantize`.
2. Compensates latency:
   `targetHost = boundaryHost − outputLatency − manualOffset`
   where `outputLatency` = `AVAudioSession.outputLatency` (iOS) /
   `outputNode.presentationLatency` (macOS) + IO buffer, exposed by
   `AudioEngine`; `manualOffset` = `latencyOffsetMs`.
3. Converts host-time → the player node's **sample time** and schedules:

```swift
// AudioEngine.scheduleSyncedLoop(pad:atHostTime:)
let render = player.lastRenderTime           // sampleTime + hostTime pair
let sr = player.outputFormat(forBus: 0).sampleRate
let secondsUntil = hostSeconds(targetHost) - hostSeconds(render.hostTime)
let targetSample = render.sampleTime + AVAudioFramePosition(secondsUntil * sr)
let when = AVAudioTime(sampleTime: targetSample, atRate: sr)
player.scheduleBuffer(buffer, at: when, options: .loops, ...)
player.play()    // node runs immediately, plays silence until `when`
```

The node is started so its render clock advances; the loop launches
sample-accurately on the beat the listener hears. If `targetSample` is already
in the past (boundary too close given latency), roll to the next boundary.

**Phase-lock (Phase 1).** Loop buffers are exactly N bars at host tempo, so
`.loops` stays phase-locked automatically while tempo is constant — we schedule
once at launch. A supervisor **re-aligns** (reschedules on the next bar
boundary) when smoothed BPM drifts past a threshold, or when `Start`/SPP
arrives (re-align to bar 1). This satisfies "phase-locked across many bars" plus
the tempo-change and Start-mid-playback edge cases without fragile per-loop
re-arming. (Per-loop re-arm is the documented alternative if mis-rendered files
must be corrected every loop — more robust, slightly higher underrun risk.)

**Quantized stop.** `queueStop(pad)` schedules the node `.stop()` for the next
boundary. A global "stop immediately" option (in `TransportSettings`) bypasses
quantization.

**Queued→playing transition.** While queued, `AppState` shows a blinking LED.
`TransportClock.onBoundaryCrossed` (active only while something is queued) tells
`SyncScheduler`/`AppState` to flip the LED to the playing/pulsing state exactly
at the boundary.

## Internal fallback (free-run)

If a synced pad is pressed while **not locked**, `AppState` plays it immediately
via the existing `audioEngine.play(pad:)` loop path — no quantization, no
internal grid, no high-resolution internal timer. The transport bar shows
`Internal @ <manual/last-known BPM>` statically. Beat-pulse visuals only run
while locked. On clock return, `TransportClock` re-locks automatically and
subsequent presses quantize again. In-flight free-run loops are left as-is (no
audio glitch); they fall under phase-lock only when next (re)launched.

## LED visuals (`MIDIManager`, driven by `AppState`)

- **Queued:** hardware pulsing LED via `setLEDPulsing` in a distinct color
  (amber) until launch.
- **Playing synced:** on `TransportClock.onBeat`, `AppState` pulses active
  synced pads' LEDs on the beat. `onBeat` is gated to fire only while synced
  pads are active, keeping main-thread hops off the hot path otherwise.

## UI

- **`TransportBarView`** (perf-facing, placed near `InstrumentStatusBar` in the
  grid view): tempo readout, Synced/Internal indicator, global `Quantization`
  selector.
- **Settings → MIDI tab** (`SettingsView`): clock-input picker (all MIDI
  sources), "Follow external clock" toggle, "Ignore Start/Stop" toggle,
  latency-offset field.
- **`PadDetailView`:** Sync toggle (Free vs Synced loop), per-pad quantize
  override picker, loop-length field (bars/beats), and a **disabled**
  "Time-stretch (Phase 2)" toggle. If the sample's measured length doesn't
  match its declared `loopLength` at the current tempo (within a tolerance),
  show an inline warning prompting the user to set the intended length.

## Persistence

`TransportSettings` persists via `UserDefaults` (JSON), owned by `AppState`.
The clock source persists by endpoint **name** and auto-reconnects on
`msgSetupChanged`. Per-pad `syncConfig` rides inside the project file.

## Testing

New `PadDeckTests` target (add to `project.yml` `testTargets`). Pure-logic
coverage:

- Tempo smoothing from synthetic host-time tick streams (steady + jittery +
  step tempo change) — assert stable, correct BPM.
- Tick count → `MusicalPosition` across time signatures.
- SPP → position (`beats × 6`).
- `nextBoundary` for each `Quantization` from arbitrary positions, including
  bar/2-bar with non-4/4 time signatures.
- Lock/dropout state transitions from tick-timing sequences.

Audio (`AVAudioPlayerNode` scheduling) and CoreMIDI receive stay build-and-run.

## Phase 2 scaffold (not implemented)

`PadSyncConfig.timeStretchEnabled` + the disabled UI toggle exist. `AudioEngine`
documents a per-pad `AVAudioUnitTimePitch` insertion point for warping a loop to
arbitrary tempos. Flagged with the added-DSP-cost note; does not block Phase 1.

## Edge cases → handling

| Edge case | Handling |
|---|---|
| Tempo change mid-set | smoothing + re-align on drift threshold; don't fight jitter |
| Clock dropout / source disappears | 500 ms lock timeout → free-run; no audio glitch; auto re-lock |
| Start mid-playback | `0xFA` resets position; queued/looping pads re-align to bar 1 |
| Non-integer-bar loop files | UI warning; user sets intended `loopLength` |
| Multiple clock sources | only the selected endpoint's port is parsed |

## Acceptance

- With a DAW/Gigmeister sending fixed-BPM clock, pressing a synced loop pad
  starts it on the next boundary and it stays phase-locked across many bars.
- Tempo readout matches the source and is stable (no jitter flicker).
- Pulling the clock falls back to internal/free-run cleanly; restoring re-locks.
- Free/one-shot pads are unchanged — still fire instantly.
- Phase 2 time-stretch is scaffolded behind a per-pad toggle, inert.
