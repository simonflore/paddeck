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
