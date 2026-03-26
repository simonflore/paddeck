import Foundation

enum InstrumentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case piano
    case drums
    case marimba
    case synthLead
    case synthPad

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .piano: "Piano"
        case .drums: "Drums"
        case .marimba: "Marimba"
        case .synthLead: "Synth Lead"
        case .synthPad: "Synth Pad"
        }
    }

    var iconName: String {
        switch self {
        case .piano: "pianokeys"
        case .drums: "drum.fill"
        case .marimba: "music.quarternote.3"
        case .synthLead: "waveform"
        case .synthPad: "waveform.path"
        }
    }

    var soundFontFilename: String {
        switch self {
        case .piano: "Piano"
        case .drums: "Drums"
        case .marimba: "Marimba"
        case .synthLead: "SynthLead"
        case .synthPad: "SynthPad"
        }
    }

    /// General MIDI program number for use with a single GM SoundFont.
    var gmProgram: UInt8 {
        switch self {
        case .piano: 0       // Acoustic Grand Piano
        case .drums: 0       // Standard Kit (uses percussion bank)
        case .marimba: 12    // Marimba
        case .synthLead: 80  // Lead 1 (square)
        case .synthPad: 88   // Pad 1 (new age)
        }
    }

    var defaultColor: LaunchpadColor {
        switch self {
        case .piano: LaunchpadColor(r: 100, g: 100, b: 127)
        case .drums: LaunchpadColor(r: 127, g: 40, b: 0)
        case .marimba: LaunchpadColor(r: 127, g: 70, b: 10)
        case .synthLead: LaunchpadColor(r: 0, g: 127, b: 30)
        case .synthPad: LaunchpadColor(r: 100, g: 0, b: 127)
        }
    }

    var noteLayout: NoteLayout {
        switch self {
        case .piano: Self.pianoLayout()
        case .drums: Self.drumsLayout()
        case .marimba: Self.marimbaLayout()
        case .synthLead: Self.isomorphicLayout(
            base: 48, rowInterval: 5,
            colorForNote: { note in
                note % 12 == 0
                    ? LaunchpadColor(r: 0, g: 127, b: 30)
                    : LaunchpadColor(r: 0, g: 40, b: 10)
            },
            pressedColor: LaunchpadColor(r: 127, g: 127, b: 127)
        )
        case .synthPad: Self.isomorphicLayout(
            base: 36, rowInterval: 7,
            colorForNote: { note in
                note % 12 == 0
                    ? LaunchpadColor(r: 100, g: 0, b: 127)
                    : LaunchpadColor(r: 30, g: 0, b: 50)
            },
            pressedColor: LaunchpadColor(r: 127, g: 127, b: 127)
        )
        }
    }
}

// Conform to EffectOption (defined in PadDetailView) for reuse in type selector UI
extension InstrumentType: EffectOption {}

// MARK: - Note Layouts

private extension InstrumentType {
    /// Black key semitones within an octave: C#=1, D#=3, F#=6, G#=8, A#=10
    static let blackKeys: Set<UInt8> = [1, 3, 6, 8, 10]

    // MARK: Piano — Isomorphic 4ths (Push-style), C2 base

    static func pianoLayout() -> NoteLayout {
        isomorphicLayout(
            base: 36, rowInterval: 5,
            colorForNote: { note in
                let semitone = UInt8(note % 12)
                if semitone == 0 {
                    // Root (C) — bright white
                    return LaunchpadColor(r: 127, g: 127, b: 127)
                } else if blackKeys.contains(semitone) {
                    // Accidentals — dark blue
                    return LaunchpadColor(r: 15, g: 15, b: 60)
                } else {
                    // Natural notes — medium blue-white
                    return LaunchpadColor(r: 60, g: 60, b: 100)
                }
            },
            pressedColor: LaunchpadColor(r: 127, g: 127, b: 127)
        )
    }

    // MARK: Marimba — Isomorphic major 3rds, C3 base

    static func marimbaLayout() -> NoteLayout {
        isomorphicLayout(
            base: 48, rowInterval: 4,
            colorForNote: { note in
                let semitone = UInt8(note % 12)
                if semitone == 0 {
                    return LaunchpadColor(r: 127, g: 80, b: 10)
                } else if blackKeys.contains(semitone) {
                    return LaunchpadColor(r: 50, g: 25, b: 5)
                } else {
                    return LaunchpadColor(r: 100, g: 55, b: 8)
                }
            },
            pressedColor: LaunchpadColor(r: 127, g: 120, b: 80)
        )
    }

    // MARK: Drums — Full 8×8 grid, GM percussion (rows 0-5 active, 6-7 off)

    static func drumsLayout() -> NoteLayout {
        // Grid[row][col] → GM drum MIDI note
        // Row 0 (bottom) = core kit, rows go up through Latin/FX
        let drumGrid: [[UInt8?]] = [
            [36, 38, 40, 37, 39, 42, 44, 46],       // Row 0: Kick, Snare, ElSnare, Rimshot, Clap, ClHH, PedalHH, OpenHH
            [35, 41, 43, 45, 47, 48, 50, 56],       // Row 1: Kick2, LoFlrTom, HiFlrTom, LoTom, LoMidTom, HiMidTom, HiTom, Cowbell
            [49, 57, 52, 55, 51, 59, 53, 54],       // Row 2: Crash1, Crash2, China, Splash, Ride1, Ride2, RideBell, Tamb
            [60, 61, 62, 63, 64, 75, 76, 77],       // Row 3: HiBongo, LoBongo, MuHiConga, OpHiConga, LoConga, Claves, HiWdBlk, LoWdBlk
            [65, 66, 67, 68, 69, 70, 58, 71],       // Row 4: HiTimb, LoTimb, HiAgogo, LoAgogo, Cabasa, Maracas, Vibraslap, ShWhistle
            [72, 73, 74, 78, 79, 80, 81, nil],      // Row 5: LgWhistle, ShGuiro, LgGuiro, MuCuica, OpCuica, MuTri, OpTri, --
            [nil, nil, nil, nil, nil, nil, nil, nil], // Row 6: inactive
            [nil, nil, nil, nil, nil, nil, nil, nil], // Row 7: inactive
        ]

        let drumColor: (UInt8) -> LaunchpadColor = { note in
            switch note {
            case 35, 36:
                return LaunchpadColor(r: 127, g: 20, b: 0)      // Kicks: red
            case 37, 38, 39, 40:
                return LaunchpadColor(r: 127, g: 60, b: 0)      // Snares/Clap: orange
            case 42, 44, 46:
                return LaunchpadColor(r: 127, g: 127, b: 0)     // Hi-hats: yellow
            case 49, 51, 52, 53, 55, 57, 59:
                return LaunchpadColor(r: 0, g: 100, b: 127)     // Cymbals/Ride: cyan
            case 41, 43, 45, 47, 48, 50:
                return LaunchpadColor(r: 0, g: 127, b: 20)      // Toms: green
            case 54, 56:
                return LaunchpadColor(r: 127, g: 100, b: 0)     // Tamb/Cowbell: gold
            default:
                return LaunchpadColor(r: 80, g: 0, b: 127)      // Latin/Percussion: purple
            }
        }

        return NoteLayout(
            noteForPosition: { pos in
                guard pos.row < drumGrid.count else { return nil }
                return drumGrid[pos.row][pos.column]
            },
            colorForPosition: { pos in
                guard pos.row < drumGrid.count,
                      let note = drumGrid[pos.row][pos.column] else { return .off }
                return drumColor(note)
            },
            pressedColor: LaunchpadColor(r: 127, g: 127, b: 127)
        )
    }

    // MARK: Isomorphic layout — configurable row interval

    static func isomorphicLayout(
        base: Int,
        rowInterval: Int,
        colorForNote: @Sendable @escaping (Int) -> LaunchpadColor,
        pressedColor: LaunchpadColor
    ) -> NoteLayout {
        NoteLayout(
            noteForPosition: { pos in
                let note = base + (pos.row * rowInterval) + pos.column
                guard note >= 0, note <= 127 else { return nil }
                return UInt8(note)
            },
            colorForPosition: { pos in
                let note = base + (pos.row * rowInterval) + pos.column
                guard note >= 0, note <= 127 else { return .off }
                return colorForNote(note)
            },
            pressedColor: pressedColor
        )
    }
}
