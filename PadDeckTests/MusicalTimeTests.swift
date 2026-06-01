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
