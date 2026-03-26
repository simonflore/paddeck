import Foundation

/// Builds SysEx messages for a specific Launchpad model.
struct LaunchpadProtocol {
    let model: LaunchpadModel

    var sysExHeader: [UInt8] {
        [0x00, 0x20, 0x29, 0x02, model.deviceId]
    }

    func programmerModeMessage() -> [UInt8] {
        [0xF0] + sysExHeader + model.programmerModePayload + [0xF7]
    }

    func liveModeMessage() -> [UInt8] {
        [0xF0] + sysExHeader + model.liveModePayload + [0xF7]
    }

    func rgbLEDMessage(note: UInt8, r: UInt8, g: UInt8, b: UInt8) -> [UInt8] {
        if model.isModernProtocol {
            return [0xF0] + sysExHeader + [0x03, 0x03, note, r, g, b, 0xF7]
        } else {
            return [0xF0] + sysExHeader + [0x0B, note, r, g, b, 0xF7]
        }
    }

    /// Build a palette-based LED message. On modern models, `type` selects the effect
    /// (0x00 static, 0x01 flashing, 0x02 pulsing). On intermediate models (MK2, Pro),
    /// `type` is ignored and the model's pulsing command (0x28) is always used.
    func paletteLEDMessage(note: UInt8, type: UInt8, colorIndex: UInt8) -> [UInt8] {
        if model.isModernProtocol {
            // Modern: lighting command 0x03 with sub-type (e.g. 0x02 for pulsing)
            return [0xF0] + sysExHeader + [0x03, type, note, colorIndex, 0xF7]
        } else {
            // Intermediate: dedicated command per effect (e.g. 0x28 for pulsing)
            return [0xF0] + sysExHeader + [model.pulsingCommand, note, colorIndex, 0xF7]
        }
    }

    /// Batch set multiple LEDs to RGB. More efficient than individual messages.
    func batchRGBMessage(entries: [(note: UInt8, r: UInt8, g: UInt8, b: UInt8)]) -> [UInt8] {
        if model.isModernProtocol {
            // Modern: 0x03 lighting command, each entry prefixed with 0x03 (RGB type)
            var msg: [UInt8] = [0xF0] + sysExHeader + [0x03]
            for entry in entries {
                msg += [0x03, entry.note, entry.r, entry.g, entry.b]
            }
            msg += [0xF7]
            return msg
        } else {
            // Intermediate: 0x0B RGB command, entries are just [note, r, g, b]
            var msg: [UInt8] = [0xF0] + sysExHeader + [0x0B]
            for entry in entries {
                msg += [entry.note, entry.r, entry.g, entry.b]
            }
            msg += [0xF7]
            return msg
        }
    }
}
