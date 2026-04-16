import Foundation

/// All supported 8×8 Novation Launchpad models.
enum LaunchpadModel: String, CaseIterable, Sendable {
    // Modern protocol (0x03 RGB format, 0x0E programmer mode)
    case launchpadX
    case miniMK3
    case proMK3

    // Intermediate protocol (0x0B RGB format, model-specific programmer mode)
    case mk2
    case proOriginal

    // Legacy protocol (original Launchpad Mini / Mini MK2 — non-RGB, no programmer mode,
    // XY note layout, velocity-encoded red/amber/green LEDs).
    case miniLegacy

    // MARK: - SysEx Constants

    /// Device-specific byte in the SysEx header `[00 20 29 02 <id>]`.
    /// Legacy Mini does not use the modern SysEx header — returns 0 and callers
    /// should consult `hasProgrammerMode` / `usesShortMessageLEDs` instead.
    var deviceId: UInt8 {
        switch self {
        case .launchpadX:  return 0x0C
        case .miniMK3:     return 0x0D
        case .proMK3:      return 0x0E
        case .mk2:         return 0x18
        case .proOriginal: return 0x10
        case .miniLegacy:  return 0x00
        }
    }

    var displayName: String {
        switch self {
        case .launchpadX:  return "Launchpad X"
        case .miniMK3:     return "Launchpad Mini MK3"
        case .proMK3:      return "Launchpad Pro MK3"
        case .mk2:         return "Launchpad MK2"
        case .proOriginal: return "Launchpad Pro"
        case .miniLegacy:  return "Launchpad Mini"
        }
    }

    /// SysEx payload bytes to enter programmer mode (after header, before F7).
    var programmerModePayload: [UInt8] {
        switch self {
        case .launchpadX, .miniMK3, .proMK3:
            return [0x0E, 0x01]
        case .mk2:
            return [0x22, 0x00]
        case .proOriginal:
            return [0x21, 0x01]
        case .miniLegacy:
            return []
        }
    }

    /// SysEx payload bytes to exit programmer mode (return to live/session).
    var liveModePayload: [UInt8] {
        switch self {
        case .launchpadX, .miniMK3, .proMK3:
            return [0x0E, 0x00]
        case .mk2:
            return [0x22, 0x01]
        case .proOriginal:
            return [0x21, 0x00]
        case .miniLegacy:
            return []
        }
    }

    /// Modern models use `0x03` lighting command; intermediate models use `0x0B`.
    /// Legacy Mini doesn't use SysEx for LEDs at all.
    var isModernProtocol: Bool {
        switch self {
        case .launchpadX, .miniMK3, .proMK3: return true
        case .mk2, .proOriginal:             return false
        case .miniLegacy:                    return false
        }
    }

    /// True if the model supports programmer-mode SysEx (11–88 note layout + RGB).
    /// Legacy Mini uses its default XY note layout and short-message LED updates.
    var hasProgrammerMode: Bool {
        self != .miniLegacy
    }

    /// True if LEDs are set via short MIDI messages (Note On / CC) rather than SysEx.
    var usesShortMessageLEDs: Bool {
        self == .miniLegacy
    }

    /// SysEx command byte for pulsing palette LED.
    /// Modern: `0x03` (lighting) with type `0x02`; Intermediate: `0x28`.
    /// Not applicable for legacy Mini (uses Note On channel 1 for flashing).
    var pulsingCommand: UInt8 {
        isModernProtocol ? 0x03 : 0x28
    }

    // MARK: - Device Detection

    /// Detect the Launchpad model from a CoreMIDI endpoint name.
    /// Checks most-specific patterns first to avoid false matches.
    static func detect(from name: String) -> LaunchpadModel? {
        let lower = name.lowercased()

        // Mini MK3 — check before generic "mini" or "launchpad"
        if lower.contains("lpminimk3") || lower.contains("mini mk3") {
            return .miniMK3
        }
        // Pro MK3 — check before generic "pro"
        if lower.contains("lppromk3") || lower.contains("pro mk3") {
            return .proMK3
        }
        // Launchpad X
        if lower.contains("lpx") || lower.contains("launchpad x") {
            return .launchpadX
        }
        // MK2 full-size (RGB) — check before generic "launchpad" / "mini"
        if lower.contains("launchpad mk2") || lower.contains("lpmk2") {
            return .mk2
        }
        // Pro (original) — "launchpad pro" without "mk3"
        if lower.contains("launchpad pro") {
            return .proOriginal
        }
        // Legacy Mini (original Mini / Mini MK2, non-RGB, USB-B) — "Launchpad Mini"
        // without MK3 suffix. Must come after the MK3 check above.
        if lower.contains("launchpad mini") || lower.contains("launchpad s") {
            return .miniLegacy
        }
        // Fallback: unrecognized "launchpad" — refuse to guess rather than
        // silently misdetect and send the wrong protocol.
        return nil
    }
}
