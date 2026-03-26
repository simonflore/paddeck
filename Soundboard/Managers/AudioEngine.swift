import AVFoundation
import Foundation

@Observable
final class AudioEngine {
    private(set) var isEngineRunning = false
    private(set) var isRecording = false
    private(set) var activePads: Set<GridPosition> = []

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var playerNodes: [GridPosition: AVAudioPlayerNode] = [:]
    private var timePitchNodes: [GridPosition: AVAudioUnitTimePitch] = [:]
    private let sampleStore: SampleStore
    private var fileCache: [String: AVAudioFile] = [:]
    private var loopBufferCache: [String: AVAudioPCMBuffer] = [:]

    // Vocal mic chain
    private let micGainNode = AVAudioMixerNode()
    private let reverbNode = AVAudioUnitReverb()
    private let delayNode = AVAudioUnitDelay()
    private let vocalPitchNode = AVAudioUnitTimePitch()
    private let distortionNode = AVAudioUnitDistortion()
    private var activeVocalEffect: VocalEffect = .reverb
    var globalMicGain: Float = 1.0

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
                    self?.activePads.remove(pad.position)
                    self?.onPadStopped?(pad.position)
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
        activePads.insert(pad.position)
    }

    func stop(at position: GridPosition) {
        playerNodes[position]?.stop()
        timePitchNodes[position]?.reset()
        activePads.remove(position)
    }

    func stopAll() {
        for (pos, player) in playerNodes {
            player.stop()
            timePitchNodes[pos]?.reset()
            activePads.remove(pos)
        }
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

    func startRecording() throws -> URL {
        if isRecording {
            engine.inputNode.removeTap(onBus: 0)
            recordingFile = nil
            isRecording = false
        }

        let url = sampleStore.generateRecordingURL()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // On-disk format: 16-bit PCM mono WAV (compatible with DSWaveformImage)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        // Specify float32 as the *processing* format so we can write float32
        // buffers from the tap — AVAudioFile converts to int16 on disk internally.
        let file = try AVAudioFile(
            forWriting: url,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.recordingFile = file
        self.recordingURL = url

        // Install tap with mono float32 format — the engine handles
        // stereo→mono downmix so buffers match the file's processingFormat.
        let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        )

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
            try? file.write(from: buffer)
        }

        isRecording = true
        return url
    }

    func stopRecording() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        recordingFile = nil
        isRecording = false
        return recordingURL
    }

    // MARK: - Vocal Mic

    func setMicActive(_ active: Bool) {
        micGainNode.volume = active ? globalMicGain : 0
    }

    func switchVocalEffect(to effect: VocalEffect) {
        guard effect != activeVocalEffect else { return }

        let oldNode = effectNode(for: activeVocalEffect)
        let newNode = effectNode(for: effect)

        // Disconnect old: micGainNode → oldNode → mixer
        engine.disconnectNodeOutput(micGainNode)
        engine.disconnectNodeOutput(oldNode)

        // Connect new: micGainNode → newNode → mixer
        engine.connect(micGainNode, to: newNode, format: nil)
        engine.connect(newNode, to: mixer, format: nil)

        activeVocalEffect = effect
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

    private func setupEngine() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        setupMicChain()
        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            print("AudioEngine failed to start: \(error)")
        }
    }

    private func setupMicChain() {
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

        // Attach all nodes (but only connect the active effect)
        engine.attach(micGainNode)
        engine.attach(reverbNode)
        engine.attach(delayNode)
        engine.attach(vocalPitchNode)
        engine.attach(distortionNode)

        micGainNode.volume = 0 // Start muted

        // Connect: inputNode → micGainNode → reverbNode (default) → mixer
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        engine.connect(engine.inputNode, to: micGainNode, format: inputFormat)
        engine.connect(micGainNode, to: reverbNode, format: nil)
        engine.connect(reverbNode, to: mixer, format: nil)

        activeVocalEffect = .reverb
    }

    private func playerNode(for position: GridPosition) -> AVAudioPlayerNode {
        if let existing = playerNodes[position] { return existing }
        let node = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        engine.attach(node)
        engine.attach(timePitch)
        engine.connect(node, to: timePitch, format: nil)
        engine.connect(timePitch, to: mixer, format: nil)
        playerNodes[position] = node
        timePitchNodes[position] = timePitch
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
