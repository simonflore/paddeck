# External MIDI Clock Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PadDeck's synced loop pads launch and loop tempo-locked to an external MIDI clock, quantized to musical boundaries, with graceful free-run fallback when no clock is present.

**Architecture:** A dedicated `ClockReceiver` (CoreMIDI adapter, own input port) parses real-time/transport bytes on the MIDI thread and feeds a `TransportClock` (`@Observable` wrapper around a pure `TransportCore` doing tempo/position/boundary math). A `SyncScheduler` converts the next musical boundary to a sample-accurate `AVAudioTime` and drives `AudioEngine.scheduleSyncedLoop`. `AppState` routes synced pad presses to the scheduler when locked, or to the existing immediate-play path when not (free-run). Pure math is unit-tested; CoreMIDI/audio/UI are build-and-run.

**Tech Stack:** Swift 5.9, SwiftUI, CoreMIDI (UMP MIDI 1.0), AVAudioEngine, XcodeGen, XCTest.

---

## File Structure

**New files:**
- `PadDeck/Models/MusicalTime.swift` — `TimeSignature`, `Quantization`, `MusicalPosition`, `MusicalLength`
- `PadDeck/Models/PadSyncConfig.swift` — per-pad sync settings
- `PadDeck/Models/TransportSettings.swift` — app-global transport/clock settings
- `PadDeck/Managers/TransportCore.swift` — pure tempo/position/boundary state machine (`TempoTracker` + `TransportCore`)
- `PadDeck/Managers/TransportClock.swift` — `@Observable` thread-safe wrapper + dropout + callbacks
- `PadDeck/Managers/ClockReceiver.swift` — CoreMIDI input adapter for the clock source
- `PadDeck/Managers/SyncScheduler.swift` — queue launches/stops, boundary→sample-time, LED-state callbacks
- `PadDeck/Views/Transport/TransportBarView.swift` — perf-facing readout + quantize selector
- `PadDeckTests/MusicalTimeTests.swift`, `TempoTrackerTests.swift`, `TransportCoreTests.swift`, `PadSyncConfigCodableTests.swift`, `TransportSettingsTests.swift`

**Modified files:**
- `PadDeck/Models/PadConfiguration.swift` — add `syncConfig`
- `PadDeck/Models/Project.swift` — carry `syncConfig`/`instrumentConfig` through `swapPads`
- `PadDeck/Managers/AudioEngine.swift` — sample-accurate synced-loop scheduling + latency accessor
- `PadDeck/App/AppState.swift` — own clock/transport/scheduler; route synced press/release; LED blink/pulse; settings accessors
- `PadDeck/Views/PadDetail/PadDetailView.swift` — sync controls + length-mismatch warning
- `PadDeck/Views/Settings/SettingsView.swift` — clock-input picker + toggles + latency offset
- `PadDeck/Views/Grid/ContentView.swift` (or `GridView.swift`) — host the transport bar
- `project.yml` — add `PadDeckTests` target

---

## Task 0: Add the unit-test target

**Files:**
- Modify: `project.yml`
- Create: `PadDeckTests/SmokeTests.swift`

- [ ] **Step 1: Add the test target to `project.yml`**

Add a `PadDeckTests` target after the `PadDeck` target, and add a `testTargets` entry to the existing `PadDeck` target's `scheme`. The `PadDeck` target currently ends with `scheme: { testTargets: [] }` — replace that empty list.

In the `targets:` map, append:

```yaml
  PadDeckTests:
    type: bundle.unit-test
    supportedDestinations: [macOS]
    sources:
      - path: PadDeckTests
    dependencies:
      - target: PadDeck
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.paddeck.tests
        GENERATE_INFOPLIST_FILE: YES
```

And change the `PadDeck` target's scheme block from:

```yaml
    scheme:
      testTargets: []
```

to:

```yaml
    scheme:
      testTargets:
        - PadDeckTests
```

- [ ] **Step 2: Create a smoke test**

`PadDeckTests/SmokeTests.swift`:

```swift
import XCTest
@testable import PadDeck

final class SmokeTests: XCTestCase {
    func testHarnessRuns() {
        XCTAssertEqual(2 + 2, 4)
    }
}
```

- [ ] **Step 3: Regenerate and run the test to verify the harness works**

Run:
```bash
xcodegen generate
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test -only-testing:PadDeckTests/SmokeTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -f project.yml PadDeckTests/SmokeTests.swift
git commit -m "test: add PadDeckTests unit-test target"
```

---

## Task 1: Musical time value types

**Files:**
- Create: `PadDeck/Models/MusicalTime.swift`
- Test: `PadDeckTests/MusicalTimeTests.swift`

- [ ] **Step 1: Write the failing tests**

`PadDeckTests/MusicalTimeTests.swift`:

```swift
import XCTest
@testable import PadDeck

final class MusicalTimeTests: XCTestCase {
    func test4_4TicksPerBeatAndBar() {
        let ts = TimeSignature()            // 4/4 default
        XCTAssertEqual(ts.ticksPerBeat, 24) // 24 PPQN per quarter
        XCTAssertEqual(ts.ticksPerBar, 96)  // 4 beats
    }

    func test6_8Ticks() {
        let ts = TimeSignature(beatsPerBar: 6, beatUnit: 8)
        XCTAssertEqual(ts.ticksPerBeat, 12) // eighth note = 12 ticks
        XCTAssertEqual(ts.ticksPerBar, 72)
    }

    func testQuantizationGrid() {
        let ts = TimeSignature()
        XCTAssertEqual(Quantization.sixteenth.ticks(in: ts), 6)
        XCTAssertEqual(Quantization.quarter.ticks(in: ts), 24)
        XCTAssertEqual(Quantization.half.ticks(in: ts), 48)
        XCTAssertEqual(Quantization.bar.ticks(in: ts), 96)
        XCTAssertEqual(Quantization.twoBars.ticks(in: ts), 192)
    }

    func testPositionFromTickCount() {
        let ts = TimeSignature()
        // tick 0 = bar 1, beat 1, tick 0 (1-based bars/beats)
        XCTAssertEqual(MusicalPosition.from(tickCount: 0, timeSignature: ts),
                       MusicalPosition(bar: 1, beat: 1, tick: 0))
        // 1 bar + 1 beat + 5 ticks = 96 + 24 + 5 = 125
        XCTAssertEqual(MusicalPosition.from(tickCount: 125, timeSignature: ts),
                       MusicalPosition(bar: 2, beat: 2, tick: 5))
    }

    func testMusicalLengthTicks() {
        let ts = TimeSignature()
        XCTAssertEqual(MusicalLength(bars: 1, beats: 0).ticks(in: ts), 96)
        XCTAssertEqual(MusicalLength(bars: 2, beats: 2).ticks(in: ts), 240)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test -only-testing:PadDeckTests/MusicalTimeTests 2>&1 | tail -20
```
Expected: FAIL — compile error, `TimeSignature` / `Quantization` undefined.

- [ ] **Step 3: Implement `MusicalTime.swift`**

`PadDeck/Models/MusicalTime.swift`:

```swift
import Foundation

/// Time signature. `beatUnit` is the note value that gets one beat (4 = quarter).
struct TimeSignature: Codable, Sendable, Equatable {
    var beatsPerBar: Int
    var beatUnit: Int

    init(beatsPerBar: Int = 4, beatUnit: Int = 4) {
        self.beatsPerBar = beatsPerBar
        self.beatUnit = beatUnit
    }

    /// Ticks per beat at 24 PPQN. 24 ticks per quarter note, scaled by beat unit.
    var ticksPerBeat: Int { 24 * 4 / beatUnit }
    var ticksPerBar: Int { ticksPerBeat * beatsPerBar }
}

/// Launch-quantization grid sizes (Ableton-style).
enum Quantization: String, Codable, CaseIterable, Sendable, Identifiable {
    case sixteenth, quarter, half, bar, twoBars

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sixteenth: "1/16"
        case .quarter:   "1/4"
        case .half:      "1/2"
        case .bar:       "1 Bar"
        case .twoBars:   "2 Bars"
        }
    }

    /// Grid size in 24-PPQN ticks. Note values are fixed; bar/2-bar scale with meter.
    func ticks(in ts: TimeSignature) -> Int {
        switch self {
        case .sixteenth: 6
        case .quarter:   24
        case .half:      48
        case .bar:       ts.ticksPerBar
        case .twoBars:   ts.ticksPerBar * 2
        }
    }
}

/// 1-based bar/beat, 0-based tick within the beat.
struct MusicalPosition: Equatable, Sendable {
    var bar: Int
    var beat: Int
    var tick: Int

    static func from(tickCount: Int, timeSignature ts: TimeSignature) -> MusicalPosition {
        let safeTicks = max(0, tickCount)
        let bar = safeTicks / ts.ticksPerBar
        let withinBar = safeTicks % ts.ticksPerBar
        let beat = withinBar / ts.ticksPerBeat
        let tick = withinBar % ts.ticksPerBeat
        return MusicalPosition(bar: bar + 1, beat: beat + 1, tick: tick)
    }
}

/// A musical length in bars + beats (per-pad loop length).
struct MusicalLength: Codable, Sendable, Equatable {
    var bars: Int
    var beats: Int

    init(bars: Int = 1, beats: Int = 0) {
        self.bars = bars
        self.beats = beats
    }

    func ticks(in ts: TimeSignature) -> Int {
        bars * ts.ticksPerBar + beats * ts.ticksPerBeat
    }
}
```

- [ ] **Step 4: Regenerate, run tests to verify they pass**

Run:
```bash
xcodegen generate
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test -only-testing:PadDeckTests/MusicalTimeTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -f PadDeck/Models/MusicalTime.swift PadDeckTests/MusicalTimeTests.swift
git commit -m "feat: add musical time value types (TimeSignature, Quantization, MusicalPosition, MusicalLength)"
```

---

## Task 2: Tempo tracker (smoothing)

**Files:**
- Create: `PadDeck/Managers/TransportCore.swift` (start with `TempoTracker`)
- Test: `PadDeckTests/TempoTrackerTests.swift`

- [ ] **Step 1: Write the failing tests**

`PadDeckTests/TempoTrackerTests.swift`:

```swift
import XCTest
@testable import PadDeck

final class TempoTrackerTests: XCTestCase {
    /// Seconds per tick for a given BPM at 24 PPQN.
    private func secPerTick(_ bpm: Double) -> Double { 60.0 / (bpm * 24.0) }

    func testSteadyClockConvergesToBPM() {
        var tracker = TempoTracker(initialBPM: 120)
        var t = 0.0
        let dt = secPerTick(140)
        for _ in 0..<60 { tracker.ingest(hostSeconds: t); t += dt }
        XCTAssertEqual(tracker.smoothedBPM, 140, accuracy: 0.5)
    }

    func testJitterDoesNotThrash() {
        var tracker = TempoTracker(initialBPM: 120)
        var t = 0.0
        let base = secPerTick(120)
        // alternating +/-15% jitter around 120 BPM
        for i in 0..<200 {
            tracker.ingest(hostSeconds: t)
            let jitter = (i % 2 == 0) ? 1.15 : 0.85
            t += base * jitter
        }
        XCTAssertEqual(tracker.smoothedBPM, 120, accuracy: 2.0)
    }

    func testResetClearsHistory() {
        var tracker = TempoTracker(initialBPM: 120)
        tracker.ingest(hostSeconds: 0)
        tracker.ingest(hostSeconds: secPerTick(180))
        tracker.reset()
        // After reset, first ingest establishes no interval yet → BPM unchanged.
        let before = tracker.smoothedBPM
        tracker.ingest(hostSeconds: 10)
        XCTAssertEqual(tracker.smoothedBPM, before, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test -only-testing:PadDeckTests/TempoTrackerTests 2>&1 | tail -20
```
Expected: FAIL — `TempoTracker` undefined.

- [ ] **Step 3: Implement `TempoTracker` in `TransportCore.swift`**

`PadDeck/Managers/TransportCore.swift`:

```swift
import Foundation

/// Smooths MIDI-clock tick intervals into a stable BPM. Pure value type.
struct TempoTracker {
    private var lastHostSeconds: Double?
    private var intervals: [Double] = []
    private let windowSize: Int
    private let maxBPMStepPerTick: Double
    private(set) var smoothedBPM: Double

    init(initialBPM: Double = 120, windowSize: Int = 24, maxBPMStepPerTick: Double = 2.0) {
        self.smoothedBPM = initialBPM
        self.windowSize = windowSize
        self.maxBPMStepPerTick = maxBPMStepPerTick
    }

    /// Feed a clock tick's host time in seconds.
    mutating func ingest(hostSeconds: Double) {
        defer { lastHostSeconds = hostSeconds }
        guard let last = lastHostSeconds else { return }
        let dt = hostSeconds - last
        guard dt > 0, dt < 2.0 else { return } // ignore non-positive / absurd gaps
        intervals.append(dt)
        if intervals.count > windowSize {
            intervals.removeFirst(intervals.count - windowSize)
        }
        let avg = intervals.reduce(0, +) / Double(intervals.count)
        let rawBPM = 60.0 / (avg * 24.0)
        let delta = rawBPM - smoothedBPM
        let clamped = max(-maxBPMStepPerTick, min(maxBPMStepPerTick, delta))
        smoothedBPM += clamped
    }

    mutating func reset() {
        lastHostSeconds = nil
        intervals.removeAll()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test -only-testing:PadDeckTests/TempoTrackerTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -f PadDeck/Managers/TransportCore.swift PadDeckTests/TempoTrackerTests.swift
git commit -m "feat: add TempoTracker clock smoothing"
```

---

## Task 3: Transport core (position + boundary state machine)

**Files:**
- Modify: `PadDeck/Managers/TransportCore.swift` (add `TransportCore`)
- Test: `PadDeckTests/TransportCoreTests.swift`

- [ ] **Step 1: Write the failing tests**

`PadDeckTests/TransportCoreTests.swift`:

```swift
import XCTest
@testable import PadDeck

final class TransportCoreTests: XCTestCase {
    private func secPerTick(_ bpm: Double) -> Double { 60.0 / (bpm * 24.0) }

    func testStartResetsAndAdvances() {
        var core = TransportCore()
        core.start()
        var t = 0.0
        let dt = secPerTick(120)
        for _ in 0..<96 { core.tick(hostSeconds: t); t += dt } // one 4/4 bar
        XCTAssertEqual(core.tickCount, 96)
        XCTAssertEqual(core.position, MusicalPosition(bar: 2, beat: 1, tick: 0))
    }

    func testTicksIgnoredWhenStopped() {
        var core = TransportCore()
        core.stop()
        core.tick(hostSeconds: 0)
        core.tick(hostSeconds: secPerTick(120))
        XCTAssertEqual(core.tickCount, 0)
    }

    func testContinueResumesWithoutReset() {
        var core = TransportCore()
        core.start()
        for i in 0..<10 { core.tick(hostSeconds: Double(i) * secPerTick(120)) }
        core.stop()
        core.continueRunning()
        core.tick(hostSeconds: 100)
        XCTAssertEqual(core.tickCount, 11)
    }

    func testSPPSetsPosition() {
        var core = TransportCore()
        core.start()
        core.setSPP(beats: 4) // 4 sixteenths = 24 ticks = beat 2 of bar 1
        XCTAssertEqual(core.tickCount, 24)
        XCTAssertEqual(core.position, MusicalPosition(bar: 1, beat: 2, tick: 0))
    }

    func testNextBoundaryTick() {
        var core = TransportCore()
        core.start()
        for i in 0..<5 { core.tick(hostSeconds: Double(i) * secPerTick(120)) } // tick 5
        // bar grid = 96; next boundary strictly after 5 is 96
        XCTAssertEqual(core.nextBoundaryTick(quantize: .bar), 96)
        // quarter grid = 24; next after 5 is 24
        XCTAssertEqual(core.nextBoundaryTick(quantize: .quarter), 24)
    }

    func testNextBoundaryOnGridAdvancesToNext() {
        var core = TransportCore()
        core.start()
        for i in 0..<24 { core.tick(hostSeconds: Double(i) * secPerTick(120)) } // tick 24, on quarter grid
        // strictly after → 48, not 24
        XCTAssertEqual(core.nextBoundaryTick(quantize: .quarter), 48)
    }

    func testSecondsUntilBoundaryUsesTempo() {
        var core = TransportCore()
        core.start()
        // establish 120 BPM, land exactly on tick 0's next bar
        var t = 0.0
        let dt = secPerTick(120)
        for _ in 0..<5 { core.tick(hostSeconds: t); t += dt }
        // 96 - 5 = 91 ticks away at secPerTick(120)
        let expected = Double(91) * secPerTick(120)
        XCTAssertEqual(core.secondsUntilBoundary(quantize: .bar), expected, accuracy: 0.002)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test -only-testing:PadDeckTests/TransportCoreTests 2>&1 | tail -20
```
Expected: FAIL — `TransportCore` undefined.

- [ ] **Step 3: Append `TransportCore` to `TransportCore.swift`**

Add to `PadDeck/Managers/TransportCore.swift`:

```swift
/// Pure transport state machine: tick counting, position, and boundary math.
struct TransportCore {
    private(set) var tickCount: Int = 0
    private(set) var isRunning: Bool = false
    var tempo = TempoTracker()
    var timeSignature = TimeSignature()

    var bpm: Double { tempo.smoothedBPM }
    var position: MusicalPosition {
        MusicalPosition.from(tickCount: tickCount, timeSignature: timeSignature)
    }

    mutating func start() {
        tickCount = 0
        isRunning = true
        tempo.reset()
    }

    mutating func continueRunning() { isRunning = true }
    mutating func stop() { isRunning = false }
    mutating func setSPP(beats: Int) { tickCount = max(0, beats) * 6 }

    /// Feed one clock tick. Always feeds tempo; advances position only while running.
    mutating func tick(hostSeconds: Double) {
        tempo.ingest(hostSeconds: hostSeconds)
        if isRunning { tickCount += 1 }
    }

    /// First grid boundary strictly after the current tick.
    func nextBoundaryTick(quantize: Quantization) -> Int {
        let grid = max(1, quantize.ticks(in: timeSignature))
        return (tickCount / grid + 1) * grid
    }

    /// Seconds until the next boundary at the current tempo.
    func secondsUntilBoundary(quantize: Quantization) -> Double {
        let secPerTick = 60.0 / (bpm * 24.0)
        let ticksAway = nextBoundaryTick(quantize: quantize) - tickCount
        return Double(ticksAway) * secPerTick
    }

    /// Length of one grid step in seconds, for roll-forward when a boundary is too close.
    func gridSeconds(quantize: Quantization) -> Double {
        let secPerTick = 60.0 / (bpm * 24.0)
        return Double(quantize.ticks(in: timeSignature)) * secPerTick
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test -only-testing:PadDeckTests/TransportCoreTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -f PadDeck/Managers/TransportCore.swift PadDeckTests/TransportCoreTests.swift
git commit -m "feat: add TransportCore position and boundary math"
```

---

## Task 4: Per-pad sync config + model wiring

**Files:**
- Create: `PadDeck/Models/PadSyncConfig.swift`
- Modify: `PadDeck/Models/PadConfiguration.swift`
- Modify: `PadDeck/Models/Project.swift:61-69` (`swapPads`)
- Test: `PadDeckTests/PadSyncConfigCodableTests.swift`

- [ ] **Step 1: Write the failing tests**

`PadDeckTests/PadSyncConfigCodableTests.swift`:

```swift
import XCTest
@testable import PadDeck

final class PadSyncConfigCodableTests: XCTestCase {
    func testOldPadJSONDecodesWithNilSyncConfig() throws {
        // A pad encoded before syncConfig existed (no syncConfig key).
        let json = """
        {"position":{"row":0,"column":0},"color":{"r":0,"g":0,"b":0},
         "playMode":"loop","volume":1.0}
        """.data(using: .utf8)!
        let pad = try JSONDecoder().decode(PadConfiguration.self, from: json)
        XCTAssertNil(pad.syncConfig)
        XCTAssertFalse(pad.isSynced)
    }

    func testSyncConfigRoundTrips() throws {
        var pad = PadConfiguration(position: GridPosition(row: 1, column: 2))
        pad.syncConfig = PadSyncConfig(
            loopLength: MusicalLength(bars: 2, beats: 0),
            quantizeOverride: .half,
            timeStretchEnabled: false
        )
        let data = try JSONEncoder().encode(pad)
        let decoded = try JSONDecoder().decode(PadConfiguration.self, from: data)
        XCTAssertEqual(decoded.syncConfig?.loopLength, MusicalLength(bars: 2, beats: 0))
        XCTAssertEqual(decoded.syncConfig?.quantizeOverride, .half)
        XCTAssertTrue(decoded.isSynced)
    }

    func testSwapPadsCarriesSyncAndInstrumentConfig() {
        var project = Project(name: "T")
        let a = GridPosition(row: 0, column: 0)
        let b = GridPosition(row: 0, column: 1)
        var padA = project.pad(at: a)
        padA.syncConfig = PadSyncConfig(loopLength: MusicalLength(bars: 1, beats: 0))
        project.setPad(padA, at: a)

        project.swapPads(a, b)
        XCTAssertNotNil(project.pad(at: b).syncConfig)
        XCTAssertNil(project.pad(at: a).syncConfig)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test -only-testing:PadDeckTests/PadSyncConfigCodableTests 2>&1 | tail -20
```
Expected: FAIL — `PadSyncConfig` / `syncConfig` / `isSynced` undefined.

- [ ] **Step 3: Create `PadSyncConfig.swift`**

`PadDeck/Models/PadSyncConfig.swift`:

```swift
import Foundation

/// Per-pad synced-loop settings. Presence on a PadConfiguration marks it "Synced".
struct PadSyncConfig: Codable, Sendable, Equatable {
    /// Declared musical length of the loop file (used for phase-lock + mismatch warning).
    var loopLength: MusicalLength
    /// Overrides the global launch quantization when non-nil.
    var quantizeOverride: Quantization?
    /// Phase 2 scaffold — inert in Phase 1.
    var timeStretchEnabled: Bool

    init(loopLength: MusicalLength = MusicalLength(bars: 1, beats: 0),
         quantizeOverride: Quantization? = nil,
         timeStretchEnabled: Bool = false) {
        self.loopLength = loopLength
        self.quantizeOverride = quantizeOverride
        self.timeStretchEnabled = timeStretchEnabled
    }
}
```

- [ ] **Step 4: Add `syncConfig` to `PadConfiguration`**

In `PadDeck/Models/PadConfiguration.swift`:

Add the stored property after `instrumentConfig` (line 11):
```swift
    var syncConfig: PadSyncConfig?
```

Add a convenience flag after `isInstrumentPad` (line 16):
```swift
    var isSynced: Bool { syncConfig != nil }
```

In the first `init(position:)`, add at the end of the body:
```swift
        self.syncConfig = nil
```

Replace the second (memberwise) initializer signature and body to include `syncConfig`:
```swift
    init(position: GridPosition, sample: Sample?, color: LaunchpadColor, playMode: PlayMode, volume: Float, emoji: String? = nil, vocalConfig: VocalPadConfig? = nil, instrumentConfig: InstrumentConfig? = nil, syncConfig: PadSyncConfig? = nil) {
        self.position = position
        self.sample = sample
        self.color = color
        self.playMode = playMode
        self.volume = volume
        self.emoji = emoji
        self.vocalConfig = vocalConfig
        self.instrumentConfig = instrumentConfig
        self.syncConfig = syncConfig
    }
```

- [ ] **Step 5: Fix `swapPads` to carry all sub-configs**

In `PadDeck/Models/Project.swift`, replace the two assignments inside `swapPads` (lines 65-67) with:
```swift
        pads[a.id] = PadConfiguration(position: a, sample: padB.sample, color: padB.color, playMode: padB.playMode, volume: padB.volume, emoji: padB.emoji, vocalConfig: padB.vocalConfig, instrumentConfig: padB.instrumentConfig, syncConfig: padB.syncConfig)
        pads[b.id] = PadConfiguration(position: b, sample: padA.sample, color: padA.color, playMode: padA.playMode, volume: padA.volume, emoji: padA.emoji, vocalConfig: padA.vocalConfig, instrumentConfig: padA.instrumentConfig, syncConfig: padA.syncConfig)
```

- [ ] **Step 6: Regenerate, run tests to verify they pass**

Run:
```bash
xcodegen generate
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test -only-testing:PadDeckTests/PadSyncConfigCodableTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -f PadDeck/Models/PadSyncConfig.swift PadDeck/Models/PadConfiguration.swift PadDeck/Models/Project.swift PadDeckTests/PadSyncConfigCodableTests.swift
git commit -m "feat: add PadSyncConfig and carry sub-configs through swapPads"
```

---

## Task 5: App-global transport settings

**Files:**
- Create: `PadDeck/Models/TransportSettings.swift`
- Test: `PadDeckTests/TransportSettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

`PadDeckTests/TransportSettingsTests.swift`:

```swift
import XCTest
@testable import PadDeck

final class TransportSettingsTests: XCTestCase {
    func testDefaults() {
        let s = TransportSettings()
        XCTAssertEqual(s.globalQuantize, .bar)
        XCTAssertEqual(s.timeSignature, TimeSignature())
        XCTAssertTrue(s.followExternalClock)
        XCTAssertFalse(s.ignoreStartStop)
        XCTAssertEqual(s.latencyOffsetMs, 0, accuracy: 0.0001)
        XCTAssertEqual(s.manualBPM, 120, accuracy: 0.0001)
        XCTAssertNil(s.clockSourceName)
        XCTAssertFalse(s.stopImmediately)
    }

    func testRoundTrips() throws {
        var s = TransportSettings()
        s.globalQuantize = .twoBars
        s.ignoreStartStop = true
        s.latencyOffsetMs = -12
        s.clockSourceName = "IAC Driver Bus 1"
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(TransportSettings.self, from: data)
        XCTAssertEqual(decoded.globalQuantize, .twoBars)
        XCTAssertTrue(decoded.ignoreStartStop)
        XCTAssertEqual(decoded.latencyOffsetMs, -12, accuracy: 0.0001)
        XCTAssertEqual(decoded.clockSourceName, "IAC Driver Bus 1")
    }

    func testPartialJSONUsesDefaults() throws {
        // Older JSON missing newer keys still decodes.
        let json = "{\"globalQuantize\":\"half\"}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TransportSettings.self, from: json)
        XCTAssertEqual(decoded.globalQuantize, .half)
        XCTAssertTrue(decoded.followExternalClock) // default preserved
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test -only-testing:PadDeckTests/TransportSettingsTests 2>&1 | tail -20
```
Expected: FAIL — `TransportSettings` undefined.

- [ ] **Step 3: Implement `TransportSettings.swift`**

`PadDeck/Models/TransportSettings.swift`. Uses a custom decoder so missing keys fall back to defaults (forward/backward compatible):

```swift
import Foundation

/// App-global transport/clock settings, persisted as JSON in UserDefaults.
struct TransportSettings: Codable, Sendable, Equatable {
    var globalQuantize: Quantization = .bar
    var timeSignature: TimeSignature = TimeSignature()
    var followExternalClock: Bool = true
    var ignoreStartStop: Bool = false
    var stopImmediately: Bool = false
    var latencyOffsetMs: Double = 0
    var manualBPM: Double = 120
    var clockSourceName: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TransportSettings()
        globalQuantize = try c.decodeIfPresent(Quantization.self, forKey: .globalQuantize) ?? d.globalQuantize
        timeSignature = try c.decodeIfPresent(TimeSignature.self, forKey: .timeSignature) ?? d.timeSignature
        followExternalClock = try c.decodeIfPresent(Bool.self, forKey: .followExternalClock) ?? d.followExternalClock
        ignoreStartStop = try c.decodeIfPresent(Bool.self, forKey: .ignoreStartStop) ?? d.ignoreStartStop
        stopImmediately = try c.decodeIfPresent(Bool.self, forKey: .stopImmediately) ?? d.stopImmediately
        latencyOffsetMs = try c.decodeIfPresent(Double.self, forKey: .latencyOffsetMs) ?? d.latencyOffsetMs
        manualBPM = try c.decodeIfPresent(Double.self, forKey: .manualBPM) ?? d.manualBPM
        clockSourceName = try c.decodeIfPresent(String.self, forKey: .clockSourceName)
    }

    private static let key = "transportSettings"

    static func load() -> TransportSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(TransportSettings.self, from: data)
        else { return TransportSettings() }
        return s
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test -only-testing:PadDeckTests/TransportSettingsTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -f PadDeck/Models/TransportSettings.swift PadDeckTests/TransportSettingsTests.swift
git commit -m "feat: add TransportSettings with UserDefaults persistence"
```

---

## Task 6: TransportClock (@Observable thread-safe wrapper)

**Files:**
- Create: `PadDeck/Managers/TransportClock.swift`

This is a CoreMIDI/threading boundary — build-and-run, no unit test.

- [ ] **Step 1: Implement `TransportClock.swift`**

`PadDeck/Managers/TransportClock.swift`:

```swift
import Foundation
import os

/// Thread-safe, observable wrapper around TransportCore. The clock receiver calls
/// the `handle*` methods from the MIDI thread; published state and callbacks are
/// delivered on the main thread.
@Observable
final class TransportClock {
    enum Status: Equatable { case synced, internalClock }

    // Main-thread-published state (read by UI).
    private(set) var status: Status = .internalClock
    private(set) var displayBPM: Double = 120
    private(set) var position: MusicalPosition = MusicalPosition(bar: 1, beat: 1, tick: 0)

    /// Fired on the main thread when status flips (synced ↔ internal).
    var onStatusChanged: ((Status) -> Void)?
    /// Fired on the main thread on each beat, ONLY while `wantsBeatEvents` is true.
    var onBeat: (() -> Void)?
    /// Fired on the main thread when playing synced loops should re-align to the
    /// downbeat: on Start/SPP, or when smoothed BPM drifts past a threshold (spec §E).
    var onResync: (() -> Void)?

    /// Gate beat callbacks so we don't hop to main 2×/sec when nothing needs it.
    @ObservationIgnored var wantsBeatEvents = false

    @ObservationIgnored var settings = TransportSettings()

    @ObservationIgnored private var core = TransportCore()
    @ObservationIgnored private var lock = os_unfair_lock()
    @ObservationIgnored private var lastTickHostSeconds: Double = 0
    @ObservationIgnored private var explicitlyStopped = false
    @ObservationIgnored private var lastBeatIndex = -1
    @ObservationIgnored private var lastResyncBPM: Double = 120
    @ObservationIgnored private var dropoutTimer: Timer?
    /// BPM change beyond this (since last resync) triggers a phase re-align.
    @ObservationIgnored private let resyncBPMThreshold: Double = 3.0

    @ObservationIgnored private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func hostToSeconds(_ host: UInt64) -> Double {
        Double(host) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000.0
    }

    func startMonitoring() {
        core.timeSignature = settings.timeSignature
        // Poll for clock dropout on the main thread.
        dropoutTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkDropout()
        }
    }

    func stopMonitoring() {
        dropoutTimer?.invalidate()
        dropoutTimer = nil
    }

    // MARK: - MIDI-thread entry points

    func handleTick(hostTime: UInt64) {
        guard settings.followExternalClock else { return } // stay Internal when off
        let seconds = Self.hostToSeconds(hostTime)
        var beatFired = false
        var newStatus: Status?
        os_unfair_lock_lock(&lock)
        lastTickHostSeconds = seconds
        // Auto-run from bare clock unless an explicit Stop is in effect.
        if !core.isRunning && !explicitlyStopped { core.continueRunning() }
        core.tick(hostSeconds: seconds)
        if status != .synced { newStatus = .synced }
        let bpm = core.bpm
        let pos = core.position
        let beatIndex = core.tickCount / max(1, core.timeSignature.ticksPerBeat)
        if beatIndex != lastBeatIndex { lastBeatIndex = beatIndex; beatFired = true }
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.displayBPM = bpm
            self.position = pos
            if let newStatus { self.applyStatus(newStatus) }
            if beatFired && self.wantsBeatEvents { self.onBeat?() }
            // Drift re-align: only while locked, only if something is following.
            if self.status == .synced && self.wantsBeatEvents
                && abs(bpm - self.lastResyncBPM) > self.resyncBPMThreshold {
                self.lastResyncBPM = bpm
                self.onResync?()
            }
        }
    }

    func handleStart() {
        guard !settings.ignoreStartStop else { return }
        os_unfair_lock_lock(&lock)
        explicitlyStopped = false
        core.start()
        lastBeatIndex = -1
        os_unfair_lock_unlock(&lock)
        DispatchQueue.main.async { [weak self] in self?.onResync?() }
    }

    func handleContinue() {
        guard !settings.ignoreStartStop else { return }
        os_unfair_lock_lock(&lock)
        explicitlyStopped = false
        core.continueRunning()
        os_unfair_lock_unlock(&lock)
    }

    func handleStop() {
        guard !settings.ignoreStartStop else { return }
        os_unfair_lock_lock(&lock)
        explicitlyStopped = true
        core.stop()
        os_unfair_lock_unlock(&lock)
    }

    func handleSPP(beats: Int) {
        os_unfair_lock_lock(&lock)
        core.setSPP(beats: beats)
        lastBeatIndex = -1
        os_unfair_lock_unlock(&lock)
        DispatchQueue.main.async { [weak self] in self?.onResync?() }
    }

    // MARK: - Scheduler reads (main thread)

    var isLocked: Bool { status == .synced }
    var currentTick: Int {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return core.tickCount
    }

    func secondsUntilBoundary(quantize: Quantization) -> Double {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return core.secondsUntilBoundary(quantize: quantize)
    }

    func gridSeconds(quantize: Quantization) -> Double {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return core.gridSeconds(quantize: quantize)
    }

    func nextBoundaryTick(quantize: Quantization) -> Int {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return core.nextBoundaryTick(quantize: quantize)
    }

    func applyTimeSignature(_ ts: TimeSignature) {
        os_unfair_lock_lock(&lock)
        core.timeSignature = ts
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Private

    private func applyStatus(_ s: Status) {
        guard status != s else { return }
        status = s
        onStatusChanged?(s)
    }

    private func checkDropout() {
        os_unfair_lock_lock(&lock)
        let last = lastTickHostSeconds
        os_unfair_lock_unlock(&lock)
        let now = Self.hostToSeconds(mach_absolute_time())
        if status == .synced && (now - last) > 0.5 {
            applyStatus(.internalClock)
        }
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run:
```bash
xcodegen generate
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add -f PadDeck/Managers/TransportClock.swift
git commit -m "feat: add TransportClock observable wrapper with dropout detection"
```

---

## Task 7: ClockReceiver (CoreMIDI input adapter)

**Files:**
- Create: `PadDeck/Managers/ClockReceiver.swift`

Build-and-run. Mirrors `MIDIManager`'s CoreMIDI patterns (UMP `._1_0`, setup-changed reconnect, name lookup).

- [ ] **Step 1: Implement `ClockReceiver.swift`**

`PadDeck/Managers/ClockReceiver.swift`:

```swift
import Foundation
import CoreMIDI

struct ClockSourceInfo: Identifiable, Hashable {
    let id: Int
    let name: String
    let source: MIDIEndpointRef
}

/// Owns its own CoreMIDI input port and connects to a user-selected clock source.
/// Parses only MIDI real-time + transport messages and forwards them to TransportClock.
@Observable
final class ClockReceiver {
    private(set) var availableSources: [ClockSourceInfo] = []
    private(set) var connectedSourceName: String?
    var isConnected: Bool { connectedSource != 0 }

    /// The transport to forward parsed events to.
    @ObservationIgnored weak var transport: TransportClock?
    /// Persisted preferred source name; the receiver reconnects to it when present.
    @ObservationIgnored var preferredSourceName: String?

    @ObservationIgnored private var client: MIDIClientRef = 0
    @ObservationIgnored private var inputPort: MIDIPortRef = 0
    @ObservationIgnored private var connectedSource: MIDIEndpointRef = 0

    init() {
        setup()
    }

    private func setup() {
        MIDIClientCreateWithBlock("PadDeckClock" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.scan() }
            }
        }
        MIDIInputPortCreateWithProtocol(client, "ClockIn" as CFString, ._1_0, &inputPort) { [weak self] eventList, _ in
            self?.handleEvents(eventList)
        }
        scan()
    }

    // MARK: - Device management

    func scan() {
        var sources: [ClockSourceInfo] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            guard let name = name(of: src) else { continue }
            sources.append(ClockSourceInfo(id: Int(src), name: name, source: src))
        }
        availableSources = sources

        // Drop a vanished connection.
        if isConnected && !sources.contains(where: { $0.source == connectedSource }) {
            disconnect()
        }
        // Auto-reconnect to the preferred source by name.
        if !isConnected, let pref = preferredSourceName,
           let match = sources.first(where: { $0.name == pref }) {
            connect(to: match)
        }
    }

    func connect(to info: ClockSourceInfo) {
        disconnect()
        if MIDIPortConnectSource(inputPort, info.source, nil) == noErr {
            connectedSource = info.source
            connectedSourceName = info.name
            preferredSourceName = info.name
        }
    }

    func disconnect() {
        if connectedSource != 0 {
            MIDIPortDisconnectSource(inputPort, connectedSource)
        }
        connectedSource = 0
        connectedSourceName = nil
    }

    // MARK: - MIDI thread parsing (minimal)

    private func handleEvents(_ listPtr: UnsafePointer<MIDIEventList>) {
        let list = listPtr.pointee
        var packet = list.packet
        guard let transport else { return }

        for _ in 0..<list.numPackets {
            let words = Mirror(reflecting: packet.words).children.compactMap { $0.value as? UInt32 }
            if let firstWord = words.first, firstWord != 0 {
                let messageType = (firstWord >> 28) & 0x0F
                // UMP type 0x1 = System Real-Time and System Common.
                if messageType == 0x01 {
                    let status = UInt8((firstWord >> 16) & 0xFF)
                    let data1 = UInt8((firstWord >> 8) & 0xFF)
                    let data2 = UInt8(firstWord & 0xFF)
                    switch status {
                    case 0xF8: transport.handleTick(hostTime: packet.timeStamp)
                    case 0xFA: transport.handleStart()
                    case 0xFB: transport.handleContinue()
                    case 0xFC: transport.handleStop()
                    case 0xF2:
                        let beats = Int(data1) | (Int(data2) << 7) // LSB, MSB
                        transport.handleSPP(beats: beats)
                    default: break // ignore other real-time/common bytes
                    }
                }
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    private func name(of endpoint: MIDIEndpointRef) -> String? {
        var cf: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &cf) == noErr,
              let cf else { return nil }
        return cf.takeRetainedValue() as String
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run:
```bash
xcodegen generate
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add -f PadDeck/Managers/ClockReceiver.swift
git commit -m "feat: add ClockReceiver CoreMIDI input adapter"
```

---

## Task 8: Sample-accurate synced-loop scheduling in AudioEngine

**Files:**
- Modify: `PadDeck/Managers/AudioEngine.swift`

Build-and-run. Adds latency accessor and `scheduleSyncedLoop(pad:afterSeconds:)`.

- [ ] **Step 1: Add an output-latency accessor**

In `PadDeck/Managers/AudioEngine.swift`, add this computed property in the `// MARK: - Playback` area (e.g. after `play(pad:velocity:)`):

```swift
    /// Total output latency in seconds (engine + session/buffer), for sync compensation.
    var outputLatencySeconds: Double {
        var latency = engine.outputNode.presentationLatency
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        latency += session.outputLatency + session.ioBufferDuration
        #endif
        return latency
    }
```

- [ ] **Step 2: Add the synced-loop scheduler method**

Add to `AudioEngine`, near the loop `play` logic:

```swift
    /// Schedule a looped pad to start `afterSeconds` from now, sample-accurately.
    /// `afterSeconds` must already be latency-compensated by the caller.
    func scheduleSyncedLoop(pad: PadConfiguration, afterSeconds: Double) {
        guard let sample = pad.sample, let file = cachedFile(for: sample) else { return }

        let key = loopBufferKey(for: sample)
        let buffer: AVAudioPCMBuffer
        if let cached = loopBufferCache[key] {
            buffer = cached
        } else {
            let sr = file.processingFormat.sampleRate
            let startFrame = AVAudioFramePosition(sample.trimStart * sr)
            let endFrame = sample.trimEnd.map { AVAudioFramePosition($0 * sr) } ?? file.length
            let frameCount = AVAudioFrameCount(endFrame - startFrame)
            guard frameCount > 0, let b = loadBuffer(from: file, startFrame: startFrame, frameCount: frameCount) else { return }
            loopBufferCache[key] = b
            buffer = b
        }

        let player = playerNode(for: pad.position)
        player.stop()
        player.volume = pad.volume

        // Ensure the node's render clock is advancing so lastRenderTime is valid.
        if !player.isPlaying { player.play() }

        let sr = player.outputFormat(forBus: 0).sampleRate
        let when: AVAudioTime?
        if let render = player.lastRenderTime, render.isSampleTimeValid, afterSeconds > 0 {
            let frames = AVAudioFramePosition(afterSeconds * sr)
            when = AVAudioTime(sampleTime: render.sampleTime + frames, atRate: sr)
        } else {
            when = nil // launch immediately if we can't anchor
        }

        player.scheduleBuffer(buffer, at: when, options: .loops, completionHandler: nil)
        player.play()

        let wasEmpty = activePads.isEmpty
        activePads.insert(pad.position)
        playingStateChanged.send(pad.position)
        #if os(iOS)
        if wasEmpty { updateDuckingState() }
        #endif
    }

    /// Stop a synced loop after `afterSeconds` (quantized stop). 0 ⇒ immediate.
    func stopSyncedLoop(at position: GridPosition, afterSeconds: Double) {
        guard afterSeconds > 0.005 else { stop(at: position); return }
        let deadline = DispatchTime.now() + afterSeconds
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            self?.stop(at: position)
        }
    }
```

> Note (Phase 2 scaffold): time-stretch would insert a per-pad `AVAudioUnitTimePitch`
> between this player node and `mixer` when `pad.syncConfig?.timeStretchEnabled` is true.
> Not wired in Phase 1; the player connects directly to `mixer` as today.

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -f PadDeck/Managers/AudioEngine.swift
git commit -m "feat: add sample-accurate synced-loop scheduling to AudioEngine"
```

---

## Task 9: SyncScheduler

**Files:**
- Create: `PadDeck/Managers/SyncScheduler.swift`

Build-and-run. Orchestrates queue→launch and quantized stop; exposes LED-state callbacks.

- [ ] **Step 1: Implement `SyncScheduler.swift`**

`PadDeck/Managers/SyncScheduler.swift`:

```swift
import Foundation

/// Bridges TransportClock boundaries to sample-accurate AudioEngine scheduling.
/// All methods run on the main actor (called from AppState).
@MainActor
final class SyncScheduler {
    private let transport: TransportClock
    private let audioEngine: AudioEngine

    /// Pads queued for launch, mapped to the boundary tick at which they start.
    private(set) var queued: [GridPosition: Int] = [:]
    /// Pads currently looping under sync.
    private(set) var playing: Set<GridPosition> = []

    /// Provides current global settings (quantize, latency offset, stop mode).
    var settings: () -> TransportSettings = { TransportSettings() }

    /// Fired when a pad is queued (AppState shows a blinking LED).
    var onQueued: ((GridPosition) -> Void)?
    /// Fired when a queued pad reaches its boundary (AppState flips LED to playing).
    var onLaunched: ((GridPosition) -> Void)?
    /// Fired when a synced pad stops.
    var onStopped: ((GridPosition) -> Void)?

    init(transport: TransportClock, audioEngine: AudioEngine) {
        self.transport = transport
        self.audioEngine = audioEngine
    }

    var hasActivity: Bool { !queued.isEmpty || !playing.isEmpty }

    func queueLaunch(_ pad: PadConfiguration) {
        let s = settings()
        let q = pad.syncConfig?.quantizeOverride ?? s.globalQuantize

        let secondsToBoundary = transport.secondsUntilBoundary(quantize: q)
        let gridSeconds = transport.gridSeconds(quantize: q)
        let latency = audioEngine.outputLatencySeconds + s.latencyOffsetMs / 1000.0

        // Compensate latency; roll forward a grid step if the boundary is too close.
        var after = secondsToBoundary - latency
        while after < 0.005 { after += max(0.01, gridSeconds) }

        audioEngine.scheduleSyncedLoop(pad: pad, afterSeconds: after)

        let boundaryTick = transport.nextBoundaryTick(quantize: q)
        queued[pad.position] = boundaryTick
        onQueued?(pad.position)
    }

    func queueStop(_ pad: PadConfiguration) {
        let s = settings()
        // Cancel a still-queued (not yet launched) pad immediately.
        if queued.removeValue(forKey: pad.position) != nil {
            audioEngine.stop(at: pad.position)
            onStopped?(pad.position)
            return
        }
        let q = pad.syncConfig?.quantizeOverride ?? s.globalQuantize
        let after = s.stopImmediately ? 0 : transport.secondsUntilBoundary(quantize: q)
        audioEngine.stopSyncedLoop(at: pad.position, afterSeconds: after)
        playing.remove(pad.position)
        onStopped?(pad.position)
    }

    func cancelAll() {
        for pos in queued.keys { audioEngine.stop(at: pos) }
        queued.removeAll()
        playing.removeAll()
    }

    /// Called on each beat (from TransportClock.onBeat) to flip queued→playing LEDs.
    /// Audio was already scheduled sample-accurately at queue time; this is visual.
    func onBeatTick() {
        guard !queued.isEmpty else { return }
        let tick = transport.currentTick
        for (pos, boundary) in queued where tick >= boundary {
            queued.removeValue(forKey: pos)
            playing.insert(pos)
            onLaunched?(pos)
        }
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run:
```bash
xcodegen generate
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add -f PadDeck/Managers/SyncScheduler.swift
git commit -m "feat: add SyncScheduler for quantized launch/stop orchestration"
```

---

## Task 10: Wire clock/transport/scheduler into AppState

**Files:**
- Modify: `PadDeck/App/AppState.swift`

Build-and-run. Owns the new managers, routes synced pad press/release, drives LED visuals, exposes settings.

- [ ] **Step 1: Add stored managers + settings to `AppState`**

In `PadDeck/App/AppState.swift`, after the existing `let instrumentEngine: InstrumentEngine` (line 59), add:

```swift
    let clockReceiver: ClockReceiver
    let transportClock: TransportClock
    let syncScheduler: SyncScheduler

    var transportSettings: TransportSettings {
        didSet {
            transportSettings.save()
            transportClock.settings = transportSettings
            transportClock.applyTimeSignature(transportSettings.timeSignature)
        }
    }
```

- [ ] **Step 2: Initialise them in `init()`**

In `init()`, after `self.instrumentEngine = InstrumentEngine(audioEngine: self.audioEngine)` (line 71), add:

```swift
        let loadedSettings = TransportSettings.load()
        let clock = TransportClock()
        clock.settings = loadedSettings
        let receiver = ClockReceiver()
        receiver.transport = clock
        receiver.preferredSourceName = loadedSettings.clockSourceName
        self.transportSettings = loadedSettings
        self.transportClock = clock
        self.clockReceiver = receiver
        self.syncScheduler = SyncScheduler(transport: clock, audioEngine: self.audioEngine)
```

At the end of `init()` (after line 84), add:

```swift
        transportClock.applyTimeSignature(loadedSettings.timeSignature)
        clockReceiver.scan()
        setupSyncCallbacks()
        transportClock.startMonitoring()
```

- [ ] **Step 3: Add the sync callback wiring**

Add this method to `AppState` (e.g. after `setupMIDICallbacks()`):

```swift
    private func setupSyncCallbacks() {
        syncScheduler.settings = { [weak self] in self?.transportSettings ?? TransportSettings() }

        syncScheduler.onQueued = { [weak self] position in
            // Blinking amber while queued.
            self?.midiManager.setLEDPulsing(at: position, colorIndex: 9)
        }
        syncScheduler.onLaunched = { [weak self] position in
            self?.midiManager.setLED(at: position, color: .playing)
        }
        syncScheduler.onStopped = { [weak self] position in
            guard let self else { return }
            let pad = self.project.pad(at: position)
            self.midiManager.setLED(at: position, color: pad.color)
        }

        transportClock.onBeat = { [weak self] in
            guard let self else { return }
            self.syncScheduler.onBeatTick()
            self.pulsePlayingSyncedPads()
        }
        transportClock.onStatusChanged = { [weak self] _ in
            self?.updateBeatEventGating()
        }
        transportClock.onResync = { [weak self] in
            self?.resyncPlayingSyncedPads()
        }
    }

    /// Re-align currently-playing synced loops to the downbeat (called on Start/SPP/drift).
    private func resyncPlayingSyncedPads() {
        guard transportClock.isLocked else { return }
        for pos in syncScheduler.playing {
            let pad = project.pad(at: pos)
            guard pad.isSynced else { continue }
            syncScheduler.queueLaunch(pad) // reschedules to the next boundary
        }
    }

    /// Enable beat callbacks only while locked AND something synced is active.
    private func updateBeatEventGating() {
        transportClock.wantsBeatEvents = transportClock.isLocked && syncScheduler.hasActivity
    }

    /// Brief bright flash on the beat for each playing synced pad.
    private func pulsePlayingSyncedPads() {
        for pos in syncScheduler.playing {
            midiManager.setLED(at: pos, color: LaunchpadColor(r: 127, g: 127, b: 127))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, self.syncScheduler.playing.contains(pos) else { return }
                self.midiManager.setLED(at: pos, color: .playing)
            }
        }
    }
```

- [ ] **Step 4: Route synced pads in `handlePadPress`**

In `handlePadPress(position:velocity:)`, replace the `.loop` case of the `switch pad.playMode` (lines 217-224) with:

```swift
        case .loop:
            if audioEngine.isPlaying(at: position) || syncScheduler.queued[position] != nil {
                // Stop: quantized for synced+locked, immediate otherwise.
                if pad.isSynced && transportClock.isLocked {
                    syncScheduler.queueStop(pad)
                } else {
                    audioEngine.stop(at: position)
                    midiManager.setLED(at: position, color: pad.color)
                }
                updateBeatEventGating()
                return
            } else if pad.isSynced && transportClock.isLocked {
                // Quantized launch.
                syncScheduler.queueLaunch(pad)
                updateBeatEventGating()
                return // LED handled by onQueued/onLaunched
            } else {
                // Free-run (synced pad with no clock, or plain loop).
                audioEngine.play(pad: pad, velocity: velocity)
            }
```

- [ ] **Step 5: Keep gating fresh on stop-all and project switch**

In `handleTopButton(index:)` `case 6: // Stop All` block, after `audioEngine.stopAll()`, add:
```swift
            syncScheduler.cancelAll()
            updateBeatEventGating()
```

In `switchProject(_:)`, after `audioEngine.stopAll()` (line 150), add:
```swift
        syncScheduler.cancelAll()
        updateBeatEventGating()
```

- [ ] **Step 6: Regenerate and build**

Run:
```bash
xcodegen generate
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -f PadDeck/App/AppState.swift
git commit -m "feat: wire clock/transport/scheduler into AppState with synced pad routing"
```

---

## Task 11: Transport bar UI

**Files:**
- Create: `PadDeck/Views/Transport/TransportBarView.swift`
- Modify: `PadDeck/Views/Grid/ContentView.swift`

Build-and-run.

- [ ] **Step 1: Implement `TransportBarView.swift`**

`PadDeck/Views/Transport/TransportBarView.swift`:

```swift
import SwiftUI

struct TransportBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            // Synced / Internal indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(appState.transportClock.isLocked ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(appState.transportClock.isLocked ? "Synced" : "Internal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            // Tempo readout
            Text(String(format: "%.1f BPM", displayedBPM))
                .font(.system(size: 13, weight: .bold, design: .monospaced))

            // Position
            let p = appState.transportClock.position
            Text(String(format: "%d.%d.%02d", p.bar, p.beat, p.tick))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer()

            // Global quantize selector
            Picker("Quantize", selection: Binding(
                get: { appState.transportSettings.globalQuantize },
                set: { appState.transportSettings.globalQuantize = $0 }
            )) {
                ForEach(Quantization.allCases) { q in
                    Text(q.displayName).tag(q)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 110)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private var displayedBPM: Double {
        appState.transportClock.isLocked
            ? appState.transportClock.displayBPM
            : appState.transportSettings.manualBPM
    }
}
```

- [ ] **Step 2: Host the bar in the main grid view**

In `PadDeck/Views/Grid/ContentView.swift`, the `gridPanel` computed property (line 60) opens with:

```swift
    private var gridPanel: some View {
        VStack(spacing: 0) {
            GridView()
                .frame(maxHeight: .infinity)
```

Insert `TransportBarView()` as the first child of that `VStack`, above `GridView()`:

```swift
    private var gridPanel: some View {
        VStack(spacing: 0) {
            TransportBarView()
            GridView()
                .frame(maxHeight: .infinity)
```

This spans the deck above the grid on macOS, iPad, and iPhone (all route through `gridPanel`).

- [ ] **Step 3: Regenerate and build for both platforms**

Run:
```bash
xcodegen generate
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -15
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 4: Manual verification**

Run the macOS app. Confirm the transport bar shows "Internal", `120.0 BPM`, position `1.1.00`, and the quantize menu lists 1/16…2 Bars and persists across relaunch.

- [ ] **Step 5: Commit**

```bash
git add -f PadDeck/Views/Transport/TransportBarView.swift PadDeck/Views/Grid/ContentView.swift
git commit -m "feat: add transport bar with tempo, sync status, and quantize selector"
```

---

## Task 12: Clock settings in the MIDI tab

**Files:**
- Modify: `PadDeck/Views/Settings/SettingsView.swift`

Build-and-run.

- [ ] **Step 1: Add a clock section to `midiTab`**

In `PadDeck/Views/Settings/SettingsView.swift`, add a second `Section` inside the `midiTab` `Form`, after the "Launchpad Connection" section:

```swift
            Section("MIDI Clock") {
                Picker("Clock Source", selection: Binding(
                    get: { appState.transportSettings.clockSourceName ?? "" },
                    set: { name in
                        appState.transportSettings.clockSourceName = name.isEmpty ? nil : name
                        appState.clockReceiver.preferredSourceName = name.isEmpty ? nil : name
                        if name.isEmpty {
                            appState.clockReceiver.disconnect()
                        } else if let src = appState.clockReceiver.availableSources.first(where: { $0.name == name }) {
                            appState.clockReceiver.connect(to: src)
                        }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(appState.clockReceiver.availableSources) { src in
                        Text(src.name).tag(src.name)
                    }
                }

                Toggle("Follow External Clock", isOn: Binding(
                    get: { appState.transportSettings.followExternalClock },
                    set: { appState.transportSettings.followExternalClock = $0 }
                ))

                // Time signature (default 4/4).
                Stepper(value: Binding(
                    get: { appState.transportSettings.timeSignature.beatsPerBar },
                    set: { appState.transportSettings.timeSignature.beatsPerBar = max(1, $0) }
                ), in: 1...16) {
                    Text("Beats per Bar: \(appState.transportSettings.timeSignature.beatsPerBar)")
                }
                Picker("Beat Unit", selection: Binding(
                    get: { appState.transportSettings.timeSignature.beatUnit },
                    set: { appState.transportSettings.timeSignature.beatUnit = $0 }
                )) {
                    ForEach([2, 4, 8, 16], id: \.self) { unit in
                        Text("1/\(unit)").tag(unit)
                    }
                }

                Toggle("Ignore Start/Stop", isOn: Binding(
                    get: { appState.transportSettings.ignoreStartStop },
                    set: { appState.transportSettings.ignoreStartStop = $0 }
                ))

                Toggle("Stop Synced Loops Immediately", isOn: Binding(
                    get: { appState.transportSettings.stopImmediately },
                    set: { appState.transportSettings.stopImmediately = $0 }
                ))

                HStack {
                    Text("Latency Offset")
                    Slider(value: Binding(
                        get: { appState.transportSettings.latencyOffsetMs },
                        set: { appState.transportSettings.latencyOffsetMs = $0 }
                    ), in: -50...50, step: 1)
                    Text("\(Int(appState.transportSettings.latencyOffsetMs)) ms")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }

                Button("Rescan MIDI Sources") {
                    appState.clockReceiver.scan()
                }
            }
```

- [ ] **Step 2: Regenerate and build**

Run:
```bash
xcodegen generate
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual verification**

Open Settings → MIDI. Confirm the Clock Source picker lists all MIDI inputs (create one with Audio MIDI Setup → IAC Driver if none), and the toggles/offset persist across relaunch.

- [ ] **Step 4: Commit**

```bash
git add -f PadDeck/Views/Settings/SettingsView.swift
git commit -m "feat: add MIDI clock source picker and sync settings to Settings"
```

---

## Task 13: Per-pad sync controls in PadDetailView

**Files:**
- Modify: `PadDeck/Views/PadDetail/PadDetailView.swift`

Build-and-run. `PadDetailView` uses a **read-only computed `pad`** (`appState.project.pad(at: position)`) and mutates via the pattern `var p = pad; p.x = …; appState.updatePad(p, at: position)`. Sections use the custom `DetailSection(title:icon:)` wrapper (NOT SwiftUI `Section`). `updatePad` already persists and preloads loop buffers. Match these idioms exactly.

- [ ] **Step 1: Add the SYNC section in the sample branch, after PLAY MODE**

In `PadDeck/Views/PadDetail/PadDetailView.swift`, inside the `} else if let sample = pad.sample {` branch, immediately after the `// Play Mode` `DetailSection` block (the one closing at line ~380), insert a sync section gated on `.loop`:

```swift
                    // Sync (loop pads only)
                    if pad.playMode == .loop {
                        DetailSection(title: "SYNC", icon: "metronome") {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle("Synced Loop", isOn: Binding(
                                    get: { pad.syncConfig != nil },
                                    set: { on in
                                        var p = pad
                                        p.syncConfig = on ? PadSyncConfig() : nil
                                        appState.updatePad(p, at: position)
                                    }
                                ))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .tint(accentColor)

                                if let sync = pad.syncConfig {
                                    // Per-pad quantize override (nil ⇒ Global).
                                    Picker("Quantize", selection: Binding(
                                        get: { sync.quantizeOverride },
                                        set: { newValue in
                                            var p = pad
                                            p.syncConfig?.quantizeOverride = newValue
                                            appState.updatePad(p, at: position)
                                        }
                                    )) {
                                        Text("Global").tag(Optional<Quantization>.none)
                                        ForEach(Quantization.allCases) { q in
                                            Text(q.displayName).tag(Optional(q))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .font(.system(size: 12, design: .rounded))

                                    // Loop length: bars and beats steppers.
                                    Stepper(value: Binding(
                                        get: { sync.loopLength.bars },
                                        set: { newBars in
                                            var p = pad
                                            p.syncConfig?.loopLength.bars = max(0, newBars)
                                            appState.updatePad(p, at: position)
                                        }
                                    ), in: 0...64) {
                                        Text("Length: \(sync.loopLength.bars) bars")
                                            .font(.system(size: 12, design: .rounded))
                                    }

                                    Stepper(value: Binding(
                                        get: { sync.loopLength.beats },
                                        set: { newBeats in
                                            var p = pad
                                            p.syncConfig?.loopLength.beats = newBeats
                                            appState.updatePad(p, at: position)
                                        }
                                    ), in: 0...(appState.transportSettings.timeSignature.beatsPerBar - 1)) {
                                        Text("+ \(sync.loopLength.beats) beats")
                                            .font(.system(size: 12, design: .rounded))
                                    }

                                    if let warning = loopLengthWarning(for: pad) {
                                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.orange)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    // Phase 2 scaffold — disabled.
                                    Toggle("Time-Stretch (Phase 2)", isOn: Binding(
                                        get: { sync.timeStretchEnabled },
                                        set: { newValue in
                                            var p = pad
                                            p.syncConfig?.timeStretchEnabled = newValue
                                            appState.updatePad(p, at: position)
                                        }
                                    ))
                                    .font(.system(size: 12, design: .rounded))
                                    .disabled(true)
                                }
                            }
                        }
                    }
```

- [ ] **Step 2: Add the length-mismatch helper**

Add this private method to `PadDetailView` (e.g. next to `volumeIcon`). It compares the sample's trimmed duration (`effectiveDuration`) against the declared length at the current tempo:

```swift
    private func loopLengthWarning(for pad: PadConfiguration) -> String? {
        guard let sync = pad.syncConfig, let sample = pad.sample else { return nil }
        let duration = sample.effectiveDuration
        let bpm = appState.transportClock.isLocked
            ? appState.transportClock.displayBPM
            : appState.transportSettings.manualBPM
        guard bpm > 0, duration > 0 else { return nil }
        let ts = appState.transportSettings.timeSignature
        let secPerTick = 60.0 / (bpm * 24.0)
        let expected = Double(sync.loopLength.ticks(in: ts)) * secPerTick
        guard expected > 0 else { return nil }
        if abs(duration / expected - 1.0) > 0.05 {
            return String(format: "File is %.2fs but %d bars %d beats at %.0f BPM = %.2fs. Set the intended length.",
                          duration, sync.loopLength.bars, sync.loopLength.beats, bpm, expected)
        }
        return nil
    }
```

- [ ] **Step 3: Regenerate and build**

Run:
```bash
xcodegen generate
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification**

Open a loop pad's detail. Toggle "Synced Loop" on → quantize/length/Phase-2 controls appear; Phase-2 toggle is disabled. Set a length that doesn't match the file → orange warning appears. Confirm settings persist (close/reopen detail and relaunch).

- [ ] **Step 5: Commit**

```bash
git add -f PadDeck/Views/PadDetail/PadDetailView.swift
git commit -m "feat: add per-pad sync controls and loop-length warning to PadDetailView"
```

---

## Task 14: End-to-end integration check + full test/build sweep

**Files:** none (verification only)

- [ ] **Step 1: Run the full unit-test suite**

Run:
```bash
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test 2>&1 | tail -25
```
Expected: `** TEST SUCCEEDED **`, all of MusicalTime/TempoTracker/TransportCore/PadSyncConfigCodable/TransportSettings/Smoke passing.

- [ ] **Step 2: Build both platforms clean**

Run:
```bash
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -10
xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 3: Acceptance walkthrough (with a clock source)**

Use a DAW or `Audio MIDI Setup → IAC Driver` + a clock generator. Verify:
- Select the clock source in Settings → MIDI; transport bar flips to "Synced @ <bpm>" and the BPM matches the source and is stable (no flicker).
- A loop pad set to "Synced Loop": pressing it blinks amber, then launches on the next bar boundary and stays phase-locked across many bars; LED pulses on the beat.
- Disable the clock generator: within ~0.5s the bar shows "Internal"; pressing a synced pad now plays immediately (free-run). Re-enable: it re-locks and quantizes again.
- With a synced loop playing, send Stop then Start (or relocate the playhead → SPP): the loop re-aligns to bar 1 on the next boundary (`onResync`).
- Nudge the master tempo by more than ~3 BPM while a synced loop plays: it re-aligns to the new grid rather than drifting; small jitter does not trigger constant restarts.
- A free / one-shot pad still fires instantly (unchanged).
- The Phase-2 time-stretch per-pad toggle is present but disabled.

- [ ] **Step 4: Commit any final touch-ups**

```bash
git add -f -A
git commit -m "test: full clock-sync suite green; integration verified" || echo "nothing to commit"
```

---

## Notes for the implementer

- **Local signing/test-host caveats (apply to every `xcodebuild` command):** the app
  target has no development team configured, so append
  `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""` to all
  `build`/`test` invocations. The `PadDeckTests` target also overrides `TEST_HOST`/
  `BUNDLE_LOADER` to the macOS bundle layout (`PadDeck.app/Contents/MacOS/PadDeck`)
  because the multiplatform app target otherwise yields an iOS-style host path. Both
  are already in `project.yml`. Example test command:
  `xcodebuild -project PadDeck.xcodeproj -scheme PadDeck -destination 'platform=macOS' test -only-testing:PadDeckTests/<Suite> CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`
- After adding **any** new file under `PadDeck/` or `PadDeckTests/`, run `xcodegen generate` before building/testing — XcodeGen globs sources at generate time.
- `docs/` is gitignored in this repo but specs/plans are force-added by convention; source files under `PadDeck/`/`PadDeckTests/` commit normally (the `-f` on test/spec/plan paths is only needed for ignored paths — plain `git add` works for source).
- All clock math is pure and unit-tested; CoreMIDI input, audio scheduling, and SwiftUI are verified build-and-run, consistent with the existing codebase.
- LED color indices for pulsing (`colorIndex: 9` amber) are cosmetic — adjust to taste against the device palette.
```
