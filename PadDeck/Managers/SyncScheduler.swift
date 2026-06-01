import Foundation

/// Bridges TransportClock boundaries to sample-accurate AudioEngine scheduling.
/// All methods run on the main actor (called from AppState).
@MainActor
final class SyncScheduler {
    private let transport: TransportClock
    private let audioEngine: AudioEngine

    /// Pads queued for launch, mapped to the boundary tick at which they start.
    private(set) var queued: [GridPosition: Int] = [:]
    /// Pads currently looping under sync.
    private(set) var playing: Set<GridPosition> = []

    /// Provides current global settings (quantize, latency offset, stop mode).
    var settings: () -> TransportSettings = { TransportSettings() }

    /// Fired when a pad is queued (AppState shows a blinking LED).
    var onQueued: ((GridPosition) -> Void)?
    /// Fired when a queued pad reaches its boundary (AppState flips LED to playing).
    var onLaunched: ((GridPosition) -> Void)?
    /// Fired when a synced pad stops.
    var onStopped: ((GridPosition) -> Void)?

    init(transport: TransportClock, audioEngine: AudioEngine) {
        self.transport = transport
        self.audioEngine = audioEngine
    }

    var hasActivity: Bool { !queued.isEmpty || !playing.isEmpty }

    func queueLaunch(_ pad: PadConfiguration) {
        let s = settings()
        let q = pad.syncConfig?.quantizeOverride ?? s.globalQuantize

        let secondsToBoundary = transport.secondsUntilBoundary(quantize: q)
        let gridSeconds = transport.gridSeconds(quantize: q)
        let latency = audioEngine.outputLatencySeconds + s.latencyOffsetMs / 1000.0

        // Compensate latency; roll forward a grid step if the boundary is too close.
        var after = secondsToBoundary - latency
        while after < 0.005 { after += max(0.01, gridSeconds) }

        audioEngine.scheduleSyncedLoop(pad: pad, afterSeconds: after)

        let boundaryTick = transport.nextBoundaryTick(quantize: q)
        queued[pad.position] = boundaryTick
        onQueued?(pad.position)
    }

    func queueStop(_ pad: PadConfiguration) {
        let s = settings()
        // Cancel a still-queued (not yet launched) pad immediately.
        if queued.removeValue(forKey: pad.position) != nil {
            audioEngine.stop(at: pad.position)
            onStopped?(pad.position)
            return
        }
        let q = pad.syncConfig?.quantizeOverride ?? s.globalQuantize
        let after = s.stopImmediately ? 0 : transport.secondsUntilBoundary(quantize: q)
        audioEngine.stopSyncedLoop(at: pad.position, afterSeconds: after)
        playing.remove(pad.position)
        onStopped?(pad.position)
    }

    func cancelAll() {
        for pos in queued.keys { audioEngine.stop(at: pos) }
        queued.removeAll()
        playing.removeAll()
    }

    /// Called on each beat (from TransportClock.onBeat) to flip queued→playing LEDs.
    /// Audio was already scheduled sample-accurately at queue time; this is visual.
    func onBeatTick() {
        guard !queued.isEmpty else { return }
        let tick = transport.currentTick
        for (pos, boundary) in queued where tick >= boundary {
            queued.removeValue(forKey: pos)
            playing.insert(pos)
            onLaunched?(pos)
        }
    }
}
