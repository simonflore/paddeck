import Foundation

/// Builds MIDI messages for a specific Launchpad model, hiding per-model
/// differences in note layout, LED transport, and SysEx framing.
struct LaunchpadProtocol {
    enum MIDIMessage {
        case sysEx([UInt8])
        /// Raw 3-byte channel-voice message: (status, data1, data2)
        case short(UInt8, UInt8, UInt8)
    }

    let model: LaunchpadModel

    // MARK: - Grid note mapping

    /// Programmer mode (modern/intermediate): `(row+1)*10 + (col+1)` → 11…88.
    /// Legacy XY mode (Mini MK1/MK2): `16 * (7-row) + col` → top-left=0, bottom-right=119.
    func gridNote(for position: GridPosition) -> UInt8 {
        switch model {
        case .miniLegacy:
            return UInt8((7 - position.row) * 16 + position.column)
        default:
            return UInt8((position.row + 1) * 10 + (position.column + 1))
        }
    }

    func gridPosition(for note: UInt8) -> GridPosition? {
        switch model {
        case .miniLegacy:
            let n = Int(note)
            let rowFromTop = n / 16
            let col = n % 16
            guard (0...7).contains(rowFromTop), (0...7).contains(col) else { return nil }
            return GridPosition(row: 7 - rowFromTop, column: col)
        default:
            return GridPosition.from(midiNote: note)
        }
    }

    // MARK: - Side column mapping

    /// Right-column side button note. App index: 0 = bottom, 7 = top.
    /// Programmer mode: 19, 29, …, 89. Legacy XY: 120, 104, …, 8.
    func sideButtonNote(for index: Int) -> UInt8 {
        switch model {
        case .miniLegacy:
            return UInt8((7 - index) * 16 + 8)
        default:
            return UInt8((index + 1) * 10 + 9)
        }
    }

    func sideButtonIndex(for note: UInt8) -> Int? {
        switch model {
        case .miniLegacy:
            let n = Int(note)
            guard n >= 8, n <= 120, (n - 8) % 16 == 0 else { return nil }
            return 7 - ((n - 8) / 16)
        default:
            let n = Int(note)
            guard n % 10 == 9, (1...8).contains(n / 10) else { return nil }
            return (n / 10) - 1
        }
    }

    // MARK: - Top row mapping

    /// Top-row button CC. App index: 0 = left, 7 = right.
    /// Programmer mode: CC 91–98. Legacy: CC 104–111.
    func topButtonCC(for index: Int) -> UInt8 {
        switch model {
        case .miniLegacy: return UInt8(104 + index)
        default:          return UInt8(91 + index)
        }
    }

    func topButtonIndex(for cc: UInt8) -> Int? {
        switch model {
        case .miniLegacy:
            guard (104...111).contains(cc) else { return nil }
            return Int(cc) - 104
        default:
            guard (91...98).contains(cc) else { return nil }
            return Int(cc) - 91
        }
    }

    // MARK: - SysEx header (modern/intermediate only)

    private var sysExHeader: [UInt8] {
        [0x00, 0x20, 0x29, 0x02, model.deviceId]
    }

    // MARK: - Programmer mode entry/exit

    func programmerModeMessages() -> [MIDIMessage] {
        if model == .miniLegacy {
            // Legacy Mini has no programmer mode; reset (CC 0 val 0) clears all
            // LEDs and returns the device to the default XY note layout.
            return [.short(0xB0, 0x00, 0x00)]
        }
        return [.sysEx([0xF0] + sysExHeader + model.programmerModePayload + [0xF7])]
    }

    func liveModeMessages() -> [MIDIMessage] {
        if model == .miniLegacy {
            return [.short(0xB0, 0x00, 0x00)]
        }
        return [.sysEx([0xF0] + sysExHeader + model.liveModePayload + [0xF7])]
    }

    // MARK: - LED messages

    /// Set a single pad or side button LED to an RGB color.
    func ledMessages(note: UInt8, r: UInt8, g: UInt8, b: UInt8) -> [MIDIMessage] {
        if model.usesShortMessageLEDs {
            return [.short(0x90, note, legacyVelocity(r: r, g: g, b: b))]
        }
        if model.isModernProtocol {
            return [.sysEx([0xF0] + sysExHeader + [0x03, 0x03, note, r, g, b, 0xF7])]
        } else {
            return [.sysEx([0xF0] + sysExHeader + [0x0B, note, r, g, b, 0xF7])]
        }
    }

    /// Set a top-row button LED to an RGB color. For legacy Mini, top-row LEDs
    /// are Control Change messages (not Note On).
    func topButtonLEDMessages(cc: UInt8, r: UInt8, g: UInt8, b: UInt8) -> [MIDIMessage] {
        if model.usesShortMessageLEDs {
            return [.short(0xB0, cc, legacyVelocity(r: r, g: g, b: b))]
        }
        if model.isModernProtocol {
            return [.sysEx([0xF0] + sysExHeader + [0x03, 0x03, cc, r, g, b, 0xF7])]
        } else {
            return [.sysEx([0xF0] + sysExHeader + [0x0B, cc, r, g, b, 0xF7])]
        }
    }

    /// Set a pulsing/flashing LED. `colorIndex` is the palette entry for modern/intermediate
    /// models; ignored on legacy (which uses an internal flash-buffer cycle, channel 2).
    func pulsingLEDMessages(note: UInt8, colorIndex: UInt8) -> [MIDIMessage] {
        if model.usesShortMessageLEDs {
            // Channel 2 Note On → legacy hardware alternates the LED between
            // buffer A (color) and buffer B (off) at the system flash rate.
            // Use a vivid amber so the pulsing state is clearly distinct from static pads.
            return [.short(0x91, note, 0x3F)]
        }
        if model.isModernProtocol {
            return [.sysEx([0xF0] + sysExHeader + [0x03, 0x02, note, colorIndex, 0xF7])]
        } else {
            return [.sysEx([0xF0] + sysExHeader + [model.pulsingCommand, note, colorIndex, 0xF7])]
        }
    }

    /// Batch-set many LEDs. Modern/intermediate collapse into a single SysEx;
    /// legacy emits one short Note On per entry.
    func batchLEDMessages(entries: [(note: UInt8, r: UInt8, g: UInt8, b: UInt8)]) -> [MIDIMessage] {
        if model.usesShortMessageLEDs {
            return entries.map { .short(0x90, $0.note, legacyVelocity(r: $0.r, g: $0.g, b: $0.b)) }
        }
        if model.isModernProtocol {
            var msg: [UInt8] = [0xF0] + sysExHeader + [0x03]
            for e in entries { msg += [0x03, e.note, e.r, e.g, e.b] }
            msg += [0xF7]
            return [.sysEx(msg)]
        } else {
            var msg: [UInt8] = [0xF0] + sysExHeader + [0x0B]
            for e in entries { msg += [e.note, e.r, e.g, e.b] }
            msg += [0xF7]
            return [.sysEx(msg)]
        }
    }

    // MARK: - Legacy color quantization

    /// Quantize an RGB color to the Launchpad S/Mini velocity byte.
    /// Legacy has only red + green LEDs; blue contributes to green (amber/green territory)
    /// so that blue-themed app colors still show up instead of going dark.
    /// Velocity bit layout: `00 gg 11 rr` — bits 2,3 = both buffers (stable display),
    /// bits 0–1 = red 0–3, bits 4–5 = green 0–3.
    private func legacyVelocity(r: UInt8, g: UInt8, b: UInt8) -> UInt8 {
        let effR = Int(r)
        let effG = min(127, Int(g) + Int(b) / 2)

        func level(_ c: Int) -> Int {
            if c < 10 { return 0 }
            if c < 48 { return 1 }
            if c < 96 { return 2 }
            return 3
        }
        let rLv = level(effR)
        let gLv = level(effG)
        if rLv == 0 && gLv == 0 { return 0x0C }
        return UInt8((gLv << 4) | 0x0C | rLv)
    }
}
