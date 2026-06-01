import AVFoundation
import Combine
import Foundation

@Observable
final class AudioEngine {
    private(set) var isEngineRunning = false
    private(set) var isRecording = false
    @ObservationIgnored private(set) var activePads: Set<GridPosition> = []
    /// Emits the position of a pad whose playing state changed (started or stopped).
    @ObservationIgnored let playingStateChanged = PassthroughSubject<GridPosition, Never>()

    /// When true, external audio is ducked while PadDeck produces sound.
    var duckingEnabled = true
    /// Whether the mic is currently routing audio to the speaker.
    @ObservationIgnored private var isMicProducingAudio = false

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()

    /// Exposed for InstrumentEngine to attach sampler nodes.
    var mixerNode: AVAudioMixerNode { mixer }
    var avAudioEngine: AVAudioEngine { engine }

    private var playerNodes: [GridPosition: AVAudioPlayerNode] = [:]
    private let sampleStore: SampleStore
    private var fileCache: [String: AVAudioFile] = [:]
    private var loopBufferCache: [String: AVAudioPCMBuffer] = [:]

    // Vocal mic chain (lazily connected)
    private let micGainNode = AVAudioMixerNode()
    private let reverbNode = AVAudioUnitReverb()
    private let delayNode = AVAudioUnitDelay()
    private let vocalPitchNode = AVAudioUnitTimePitch()
    private let distortionNode = AVAudioUnitDistortion()
    private var activeVocalEffect: VocalEffect = .reverb
    private(set) var globalMicGain: Float = 1.0
    private var isMicChainReady = false

    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?

    /// Called on main thread when a pad stops playing (for LED sync).
    var onPadStopped: ((GridPosition) -> Void)?

    init(sampleStore: SampleStore) {
        self.sampleStore = sampleStore
        setupEngine()
    }

    // MARK: - Playback

    /// Play a pad with velocity-sensitive volume.
    /// Velocity (0-127) modulates the pad's configured volume — identical
    /// to how MIDI velocity works on a Launchpad, but also driven by
    /// Force Touch pressure from the MacBook trackpad.
    func play(pad: PadConfiguration, velocity: UInt8 = 127) {
        guard let sample = pad.sample else { return }

        let file: AVAudioFile?
        switch pad.playMode {
        case .oneShot, .oneShotStopOnRelease:
            file = freshFile(for: sample)
        case .loop:
            file = cachedFile(for: sample)
        }
        guard let file else { return }

        let player = playerNode(for: pad.position)
        player.stop()

        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(sample.trimStart * sampleRate)
        let endFrame: AVAudioFramePosition
        if let trimEnd = sample.trimEnd {
            endFrame = AVAudioFramePosition(trimEnd * sampleRate)
        } else {
            endFrame = file.length
        }
        let frameCount = AVAudioFrameCount(endFrame - startFrame)
        guard frameCount > 0 else { return }

        switch pad.playMode {
        case .oneShot, .oneShotStopOnRelease:
            player.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: frameCount,
                at: nil
            ) { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.activePads.remove(pad.position)
                    self.playingStateChanged.send(pad.position)
                    #if os(iOS)
                    if self.activePads.isEmpty { self.updateDuckingState() }
                    #endif
                    self.onPadStopped?(pad.position)
                }
            }
        case .loop:
            let key = loopBufferKey(for: sample)
            let buffer: AVAudioPCMBuffer?
            if let cached = loopBufferCache[key] {
                buffer = cached
            } else {
                buffer = loadBuffer(from: file, startFrame: startFrame, frameCount: frameCount)
                if let b = buffer { loopBufferCache[key] = b }
            }
            if let buffer {
                player.scheduleBuffer(buffer, at: nil, options: .loops)
            }
        }

        // Velocity modulates the pad's configured volume:
        // vel 127 = full configured volume, vel 1 = ~0.8% of configured volume
        let velocityScale = Float(max(velocity, 1)) / 127.0
        player.volume = pad.volume * velocityScale
        player.play()
        let wasEmpty = activePads.isEmpty
        activePads.insert(pad.position)
        playingStateChanged.send(pad.position)
        #if os(iOS)
        if wasEmpty { updateDuckingState() }
        #endif
    }

    /// Total output latency in seconds (engine + session/buffer), for sync compensation.
    var outputLatencySeconds: Double {
        var latency = engine.outputNode.presentationLatency
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        latency += session.outputLatency + session.ioBufferDuration
        #endif
        return latency
    }

    /// Schedule a looped pad to start `afterSeconds` from now, sample-accurately.
    /// `afterSeconds` must already be latency-compensated by the caller.
    func scheduleSyncedLoop(pad: PadConfiguration, afterSeconds: Double) {
        guard let sample = pad.sample, let file = cachedFile(for: sample) else { return }

        let key = loopBufferKey(for: sample)
        let buffer: AVAudioPCMBuffer
        if let cached = loopBufferCache[key] {
            buffer = cached
        } else {
            let sr = file.processingFormat.sampleRate
            let startFrame = AVAudioFramePosition(sample.trimStart * sr)
            let endFrame = sample.trimEnd.map { AVAudioFramePosition($0 * sr) } ?? file.length
            let frameCount = AVAudioFrameCount(endFrame - startFrame)
            guard frameCount > 0, let b = loadBuffer(from: file, startFrame: startFrame, frameCount: frameCount) else { return }
            loopBufferCache[key] = b
            buffer = b
        }

        let player = playerNode(for: pad.position)
        player.stop()
        player.volume = pad.volume

        // Ensure the node's render clock is advancing so lastRenderTime is valid.
        if !player.isPlaying { player.play() }

        let sr = player.outputFormat(forBus: 0).sampleRate
        let when: AVAudioTime?
        if let render = player.lastRenderTime, render.isSampleTimeValid, afterSeconds > 0 {
            let frames = AVAudioFramePosition(afterSeconds * sr)
            when = AVAudioTime(sampleTime: render.sampleTime + frames, atRate: sr)
        } else {
            when = nil // launch immediately if we can't anchor
        }

        player.scheduleBuffer(buffer, at: when, options: .loops, completionHandler: nil)
        player.play()

        let wasEmpty = activePads.isEmpty
        activePads.insert(pad.position)
        playingStateChanged.send(pad.position)
        #if os(iOS)
        if wasEmpty { updateDuckingState() }
        #endif
    }

    /// Stop a synced loop after `afterSeconds` (quantized stop). 0 ⇒ immediate.
    func stopSyncedLoop(at position: GridPosition, afterSeconds: Double) {
        guard afterSeconds > 0.005 else { stop(at: position); return }
        let deadline = DispatchTime.now() + afterSeconds
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            self?.stop(at: position)
        }
    }

    func stop(at position: GridPosition) {
        playerNodes[position]?.stop()
        activePads.remove(position)
        playingStateChanged.send(position)
        #if os(iOS)
        if activePads.isEmpty { updateDuckingState() }
        #endif
    }

    func stopAll() {
        let wasPlaying = activePads
        for (_, player) in playerNodes {
            player.stop()
        }
        activePads.removeAll()
        for pos in wasPlaying {
            playingStateChanged.send(pos)
        }
        #if os(iOS)
        if !wasPlaying.isEmpty { updateDuckingState() }
        #endif
    }

    func isPlaying(at position: GridPosition) -> Bool {
        activePads.contains(position)
    }

    // MARK: - Cache Management

    func invalidateFileCache(for sampleID: String) {
        fileCache.removeValue(forKey: sampleID)
        loopBufferCache = loopBufferCache.filter { !$0.key.hasPrefix(sampleID) }
    }

    func invalidateAllCaches() {
        fileCache.removeAll()
        loopBufferCache.removeAll()
    }

    // MARK: - Recording

    enum RecordingError: LocalizedError {
        case microphoneUnavailable

        var errorDescription: String? {
            switch self {
            case .microphoneUnavailable:
                return "Microphone not available. Check System Settings > Privacy & Security > Microphone."
            }
        }
    }

    func startRecording() throws -> URL {
        ensureMicChainConnected()
        guard isMicChainReady else {
            throw RecordingError.microphoneUnavailable
        }
        if isRecording {
            micGainNode.removeTap(onBus: 0)
            recordingFile = nil
            isRecording = false
        }

        let url = sampleStore.generateRecordingURL()
        let nodeFormat = micGainNode.outputFormat(forBus: 0)
        guard nodeFormat.sampleRate > 0, nodeFormat.channelCount > 0 else {
            throw RecordingError.microphoneUnavailable
        }

        // On-disk format: 16-bit PCM WAV, matching the node's channel count.
        // Using the node's native channel count avoids a format mismatch crash
        // when installTap tries to set a different format on the bus.
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: nodeFormat.sampleRate,
            AVNumberOfChannelsKey: nodeFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        // Processing format matches node output so tap buffers can be written
        // directly. AVAudioFile converts to int16 on disk internally.
        let file = try AVAudioFile(
            forWriting: url,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.recordingFile = file
        self.recordingURL = url

        // Use nil format — matches the node's native bus format and avoids
        // the SetFormat crash (-10865) from forcing a different channel count.
        micGainNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            try? file.write(from: buffer)
        }

        isRecording = true
        return url
    }

    func stopRecording() -> URL? {
        micGainNode.removeTap(onBus: 0)
        recordingFile = nil
        isRecording = false
        return recordingURL
    }

    // MARK: - Vocal Mic

    func setMicActive(_ active: Bool) {
        if active { ensureMicChainConnected() }
        micGainNode.volume = active ? globalMicGain : 0
        isMicProducingAudio = active
        #if os(iOS)
        updateDuckingState()
        #endif
    }

    func switchVocalEffect(to effect: VocalEffect) {
        guard effect != activeVocalEffect else { return }
        ensureMicChainConnected()
        guard isMicChainReady else { return }

        let oldNode = effectNode(for: activeVocalEffect)
        let newNode = effectNode(for: effect)

        // Mute during switch to avoid glitches from live disconnection
        let savedVolume = micGainNode.volume
        micGainNode.volume = 0

        // Only rewire micGainNode → effect → mixer (inputNode stays connected)
        engine.disconnectNodeOutput(micGainNode)
        engine.disconnectNodeOutput(oldNode)

        engine.connect(micGainNode, to: newNode, format: nil)
        engine.connect(newNode, to: mixer, format: nil)

        activeVocalEffect = effect
        micGainNode.volume = savedVolume
    }

    /// AVAudioUnitTimePitch has no wetDryMix — pitch shift is always 100% wet.
    var activeEffectSupportsDryWet: Bool {
        activeVocalEffect != .pitchShift
    }

    func setVocalDryWet(_ value: Float) {
        let node = effectNode(for: activeVocalEffect)
        if let reverb = node as? AVAudioUnitReverb {
            reverb.wetDryMix = value * 100
        } else if let delay = node as? AVAudioUnitDelay {
            delay.wetDryMix = value * 100
        } else if let dist = node as? AVAudioUnitDistortion {
            dist.wetDryMix = value * 100
        }
        // pitchShift: no wetDryMix available — always 100% wet
    }

    func setMicGain(_ gain: Float) {
        globalMicGain = gain
        // Update live volume if mic is currently unmuted
        if micGainNode.volume > 0 {
            micGainNode.volume = gain
        }
    }

    private func effectNode(for effect: VocalEffect) -> AVAudioNode {
        switch effect {
        case .reverb: reverbNode
        case .delay: delayNode
        case .pitchShift: vocalPitchNode
        case .distortion: distortionNode
        }
    }

    // MARK: - Private

    #if os(iOS)
    /// Base options always applied to the audio session.
    private let baseSessionOptions: AVAudioSession.CategoryOptions = [
        .defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers
    ]

    /// Returns true when PadDeck is actively producing audible output.
    private var isProducingAudio: Bool {
        !activePads.isEmpty || isMicProducingAudio
    }

    /// Reconfigures the audio session to add or remove `.duckOthers`
    /// based on whether PadDeck is producing sound and ducking is enabled.
    private func updateDuckingState() {
        let shouldDuck = duckingEnabled && isProducingAudio
        var options = baseSessionOptions
        if shouldDuck { options.insert(.duckOthers) }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: options)
        } catch {
            print("AVAudioSession setCategory failed: \(error)")
        }
    }
    #endif

    private func setupEngine() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: baseSessionOptions)
            try session.setActive(true)
        } catch {
            print("AVAudioSession setup failed: \(error)")
        }
        #endif

        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            print("AudioEngine failed to start: \(error)")
        }

        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleSessionInterruption(notification)
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
        #endif
    }

    #if os(iOS)
    private func handleSessionInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            let options = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                try? AVAudioSession.sharedInstance().setActive(true)
                try? engine.start()
                isEngineRunning = true
            }
        } else {
            isEngineRunning = false
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        if reason == .oldDeviceUnavailable {
            // Headphones/Bluetooth disconnected — restart engine to reconfigure
            try? AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                try? engine.start()
                isEngineRunning = true
            }
        }
    }
    #endif

    /// Attaches and connects the mic → effect → mixer chain.
    /// Called lazily the first time a vocal pad is activated or recording starts.
    /// Must stop/restart the engine to safely wire inputNode on macOS.
    ///
    /// On macOS, accessing `engine.inputNode` triggers a synchronous TCC
    /// microphone permission check that blocks the calling thread. Callers
    /// MUST request permission via `AVCaptureDevice.requestAccess(for: .audio)`
    /// before invoking any method that reaches this path. If permission has not
    /// been determined yet, this method bails out to avoid a main-thread deadlock.
    private func ensureMicChainConnected() {
        guard !isMicChainReady else { return }

        #if os(macOS)
        // Guard against the synchronous TCC deadlock: if the user hasn't
        // responded to the mic permission prompt yet, do NOT touch inputNode.
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard micStatus == .authorized else {
            if micStatus == .notDetermined {
                print("[AudioEngine] Mic permission not yet determined — deferring mic chain setup")
            } else {
                print("[AudioEngine] Mic permission denied/restricted — mic chain disabled")
            }
            return
        }
        #endif

        // Configure effect defaults
        reverbNode.loadFactoryPreset(.largeHall2)
        reverbNode.wetDryMix = 50

        delayNode.delayTime = 0.3
        delayNode.feedback = 30
        delayNode.lowPassCutoff = 15000
        delayNode.wetDryMix = 50

        vocalPitchNode.pitch = 1200 // +1 octave

        distortionNode.loadFactoryPreset(.speechWaves)
        distortionNode.wetDryMix = 50

        // Attach all effect nodes
        engine.attach(micGainNode)
        engine.attach(reverbNode)
        engine.attach(delayNode)
        engine.attach(vocalPitchNode)
        engine.attach(distortionNode)

        micGainNode.volume = 0

        // Stop the engine before wiring inputNode — accessing inputNode while
        // the engine is running can deadlock on macOS (render thread holds the
        // graph lock while main thread tries to reconfigure).
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            print("[AudioEngine] No microphone input available — vocal chain disabled")
            if wasRunning { try? engine.start() }
            return
        }
        engine.connect(engine.inputNode, to: micGainNode, format: inputFormat)
        engine.connect(micGainNode, to: reverbNode, format: nil)
        engine.connect(reverbNode, to: mixer, format: nil)

        activeVocalEffect = .reverb
        isMicChainReady = true

        if wasRunning { try? engine.start() }
    }

    private func playerNode(for position: GridPosition) -> AVAudioPlayerNode {
        if let existing = playerNodes[position] { return existing }
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: mixer, format: nil)
        playerNodes[position] = node
        return node
    }

    private func loadBuffer(
        from file: AVAudioFile,
        startFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        file.framePosition = startFrame
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else { return nil }
        try? file.read(into: buffer, frameCount: frameCount)
        return buffer
    }

    private func cachedFile(for sample: Sample) -> AVAudioFile? {
        let key = sample.id.uuidString
        if let cached = fileCache[key] { return cached }
        guard let url = sampleStore.audioFileURL(for: sample),
              let file = try? AVAudioFile(forReading: url) else { return nil }
        fileCache[key] = file
        return file
    }

    /// Open a fresh AVAudioFile for one-shot playback (avoids framePosition race on shared file).
    private func freshFile(for sample: Sample) -> AVAudioFile? {
        guard let url = sampleStore.audioFileURL(for: sample) else { return nil }
        return try? AVAudioFile(forReading: url)
    }

    private func loopBufferKey(for sample: Sample) -> String {
        let end = sample.trimEnd.map { String(format: "%.6f", $0) } ?? "nil"
        return "\(sample.id.uuidString)_\(String(format: "%.6f", sample.trimStart))_\(end)"
    }

    func preloadLoopBuffer(for pad: PadConfiguration) {
        guard pad.playMode == .loop,
              let sample = pad.sample,
              let file = cachedFile(for: sample) else { return }

        let key = loopBufferKey(for: sample)
        guard loopBufferCache[key] == nil else { return }

        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(sample.trimStart * sampleRate)
        let endFrame: AVAudioFramePosition
        if let trimEnd = sample.trimEnd {
            endFrame = AVAudioFramePosition(trimEnd * sampleRate)
        } else {
            endFrame = file.length
        }
        let frameCount = AVAudioFrameCount(endFrame - startFrame)
        guard frameCount > 0 else { return }

        if let buffer = loadBuffer(from: file, startFrame: startFrame, frameCount: frameCount) {
            loopBufferCache[key] = buffer
        }
    }
}
