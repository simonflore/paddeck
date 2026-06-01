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
