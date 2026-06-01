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
