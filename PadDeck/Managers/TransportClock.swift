import Foundation
import os

/// Thread-safe, observable wrapper around TransportCore. The clock receiver calls
/// the `handle*` methods from the MIDI thread; published state and callbacks are
/// delivered on the main thread.
@Observable
final class TransportClock {
    enum Status: Equatable { case synced, internalClock }

    // Main-thread-published state (read by UI).
    private(set) var status: Status = .internalClock
    private(set) var displayBPM: Double = 120
    private(set) var position: MusicalPosition = MusicalPosition(bar: 1, beat: 1, tick: 0)

    /// Fired on the main thread when status flips (synced ↔ internal).
    var onStatusChanged: ((Status) -> Void)?
    /// Fired on the main thread on each beat, ONLY while `wantsBeatEvents` is true.
    var onBeat: (() -> Void)?
    /// Fired on the main thread when playing synced loops should re-align to the
    /// downbeat: on Start/SPP, or when smoothed BPM drifts past a threshold (spec §E).
    var onResync: (() -> Void)?

    /// Gate beat callbacks so we don't hop to main 2×/sec when nothing needs it.
    @ObservationIgnored var wantsBeatEvents = false

    @ObservationIgnored var settings = TransportSettings()

    @ObservationIgnored private var core = TransportCore()
    @ObservationIgnored private var lock = os_unfair_lock()
    @ObservationIgnored private var lastTickHostSeconds: Double = 0
    @ObservationIgnored private var explicitlyStopped = false
    @ObservationIgnored private var lastBeatIndex = -1
    @ObservationIgnored private var lastResyncBPM: Double = 120
    @ObservationIgnored private var dropoutTimer: Timer?
    /// BPM change beyond this (since last resync) triggers a phase re-align.
    @ObservationIgnored private let resyncBPMThreshold: Double = 3.0

    @ObservationIgnored private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func hostToSeconds(_ host: UInt64) -> Double {
        Double(host) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000.0
    }

    func startMonitoring() {
        core.timeSignature = settings.timeSignature
        // Poll for clock dropout on the main thread.
        dropoutTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkDropout()
        }
    }

    func stopMonitoring() {
        dropoutTimer?.invalidate()
        dropoutTimer = nil
    }

    // MARK: - MIDI-thread entry points

    func handleTick(hostTime: UInt64) {
        guard settings.followExternalClock else { return } // stay Internal when off
        let seconds = Self.hostToSeconds(hostTime)
        var beatFired = false
        var newStatus: Status?
        os_unfair_lock_lock(&lock)
        lastTickHostSeconds = seconds
        // Auto-run from bare clock unless an explicit Stop is in effect.
        if !core.isRunning && !explicitlyStopped { core.continueRunning() }
        core.tick(hostSeconds: seconds)
        if status != .synced { newStatus = .synced }
        let bpm = core.bpm
        let pos = core.position
        let beatIndex = core.tickCount / max(1, core.timeSignature.ticksPerBeat)
        if beatIndex != lastBeatIndex { lastBeatIndex = beatIndex; beatFired = true }
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.displayBPM = bpm
            self.position = pos
            if let newStatus { self.applyStatus(newStatus) }
            if beatFired && self.wantsBeatEvents { self.onBeat?() }
            // Drift re-align: only while locked, only if something is following.
            if self.status == .synced && self.wantsBeatEvents
                && abs(bpm - self.lastResyncBPM) > self.resyncBPMThreshold {
                self.lastResyncBPM = bpm
                self.onResync?()
            }
        }
    }

    func handleStart() {
        guard !settings.ignoreStartStop else { return }
        os_unfair_lock_lock(&lock)
        explicitlyStopped = false
        core.start()
        lastBeatIndex = -1
        os_unfair_lock_unlock(&lock)
        DispatchQueue.main.async { [weak self] in self?.onResync?() }
    }

    func handleContinue() {
        guard !settings.ignoreStartStop else { return }
        os_unfair_lock_lock(&lock)
        explicitlyStopped = false
        core.continueRunning()
        os_unfair_lock_unlock(&lock)
    }

    func handleStop() {
        guard !settings.ignoreStartStop else { return }
        os_unfair_lock_lock(&lock)
        explicitlyStopped = true
        core.stop()
        os_unfair_lock_unlock(&lock)
    }

    func handleSPP(beats: Int) {
        os_unfair_lock_lock(&lock)
        core.setSPP(beats: beats)
        lastBeatIndex = -1
        os_unfair_lock_unlock(&lock)
        DispatchQueue.main.async { [weak self] in self?.onResync?() }
    }

    // MARK: - Scheduler reads (main thread)

    var isLocked: Bool { status == .synced }
    var currentTick: Int {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return core.tickCount
    }

    func secondsUntilBoundary(quantize: Quantization) -> Double {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return core.secondsUntilBoundary(quantize: quantize)
    }

    func gridSeconds(quantize: Quantization) -> Double {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return core.gridSeconds(quantize: quantize)
    }

    func nextBoundaryTick(quantize: Quantization) -> Int {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return core.nextBoundaryTick(quantize: quantize)
    }

    func applyTimeSignature(_ ts: TimeSignature) {
        os_unfair_lock_lock(&lock)
        core.timeSignature = ts
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Private

    private func applyStatus(_ s: Status) {
        guard status != s else { return }
        status = s
        onStatusChanged?(s)
    }

    private func checkDropout() {
        os_unfair_lock_lock(&lock)
        let last = lastTickHostSeconds
        os_unfair_lock_unlock(&lock)
        let now = Self.hostToSeconds(mach_absolute_time())
        if status == .synced && (now - last) > 0.5 {
            applyStatus(.internalClock)
        }
    }
}
