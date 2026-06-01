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
