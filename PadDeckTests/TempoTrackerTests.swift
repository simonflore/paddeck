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
