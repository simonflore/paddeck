#if os(macOS)
import AppKit

/// Captures Force Touch pressure from the MacBook trackpad.
///
/// On trackpads with Force Touch, pressure ranges from 0.0 (feather touch)
/// to 1.0 (deep press). Regular mice always report ~1.0 on mouseDown,
/// so they default to maximum velocity — a perfect fallback.
///
/// Usage: Read `PressureTracker.shared.lastPressure` immediately after
/// a mouse-down event to get the pressure of the click that just happened.
final class PressureTracker {
    static let shared = PressureTracker()

    /// The pressure of the most recent mouse-down event (0.0–1.0).
    private(set) var lastPressure: Float = 1.0

    private var monitor: Any?

    private init() {
        // Monitor left mouse-down events to capture pressure at click time.
        // `pressure` events fire during Force Touch deepening, but the
        // initial mouseDown already contains a useful pressure reading.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.lastPressure = event.pressure
            return event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// Convert the last captured pressure (0.0–1.0) to a MIDI velocity (1–127).
    /// Applies a slight curve so light taps still produce audible output.
    var velocity: UInt8 {
        // Clamp and apply a sqrt curve for a more musical feel:
        // light taps (~0.1 pressure) → vel ~40 instead of ~13
        let clamped = max(0.0, min(1.0, lastPressure))
        let curved = sqrt(clamped)
        return UInt8(max(1, min(127, curved * 127.0)))
    }
}

#else

/// Stub for platforms without Force Touch (iOS/iPadOS).
/// Always returns full velocity since touch pressure isn't available.
final class PressureTracker {
    static let shared = PressureTracker()
    var velocity: UInt8 { 127 }
}

#endif
