import Foundation
import CoreMIDI

struct MIDIDeviceInfo: Identifiable, Hashable {
    let id: Int
    let name: String
    let source: MIDIEndpointRef
    let destination: MIDIEndpointRef
}

@Observable
final class MIDIManager {
    private(set) var isConnected = false
    private(set) var deviceName = "No device"
    private(set) var availableDevices: [MIDIDeviceInfo] = []

    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    private var inputPort: MIDIPortRef = 0
    private var connectedSource: MIDIEndpointRef = 0
    private var connectedDestination: MIDIEndpointRef = 0

    var onPadPressed: ((GridPosition, UInt8) -> Void)?
    var onPadReleased: ((GridPosition) -> Void)?
    var onSideButtonPressed: ((UInt8) -> Void)?
    var onDeviceConnected: (() -> Void)?

    init() {
        setupMIDI(initialScan: false)
    }

    // MARK: - Public

    func scanForDevices() {
        var devices: [MIDIDeviceInfo] = []
        let sourceCount = MIDIGetNumberOfSources()
        let destCount = MIDIGetNumberOfDestinations()

        #if DEBUG
        print("[MIDI] Scan: \(sourceCount) sources, \(destCount) destinations")
        #endif

        // Build a map of destination names to endpoints
        var destMap: [String: MIDIEndpointRef] = [:]
        for i in 0..<destCount {
            let dest = MIDIGetDestination(i)
            if let name = getMIDIName(dest) {
                #if DEBUG
                print("[MIDI]   dest[\(i)]: \"\(name)\"")
                #endif
                destMap[name] = dest
            }
        }

        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            guard let name = getMIDIName(source) else { continue }
            #if DEBUG
            print("[MIDI]   source[\(i)]: \"\(name)\" (match: \(isLaunchpadName(name)))")
            #endif
            guard isLaunchpadName(name) else { continue }

            // Pair source with destination by matching port type (MIDI↔MIDI, DAW↔DAW)
            let portType = portSuffix(name)
            if let dest = destMap.first(where: { isLaunchpadName($0.key) && portSuffix($0.key) == portType })?.value {
                devices.append(MIDIDeviceInfo(
                    id: Int(source),
                    name: name,
                    source: source,
                    destination: dest
                ))
            }
        }

        // Prefer MIDI port over DAW port
        devices.sort { a, b in
            let aIsMIDI = a.name.lowercased().contains("midi")
            let bIsMIDI = b.name.lowercased().contains("midi")
            return aIsMIDI && !bIsMIDI
        }

        availableDevices = devices

        // Auto-disconnect if the connected device disappeared
        if isConnected && !devices.contains(where: { $0.source == connectedSource }) {
            disconnect()
        }

        // Auto-connect if not already connected and a device is available
        if !isConnected, let device = devices.first {
            connect(to: device)
            onDeviceConnected?()
        }
    }

    private func isLaunchpadName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("launchpad") || lower.contains("lpx") || lower.contains("lpmini")
    }

    /// Returns "midi" or "daw" to pair matching source/destination ports
    private func portSuffix(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("daw") { return "daw" }
        return "midi"
    }

    func connect(to device: MIDIDeviceInfo) {
        disconnect()

        connectedSource = device.source
        connectedDestination = device.destination

        let status = MIDIPortConnectSource(inputPort, connectedSource, nil)
        if status == noErr {
            isConnected = true
            deviceName = device.name
        }
    }

    func disconnect() {
        if connectedSource != 0 {
            MIDIPortDisconnectSource(inputPort, connectedSource)
        }
        isConnected = false
        deviceName = "No device"
        connectedSource = 0
        connectedDestination = 0
    }

    func enterProgrammerMode() {
        sendSysEx(LaunchpadProtocol.programmerModeMessage())
    }

    func exitProgrammerMode() {
        sendSysEx(LaunchpadProtocol.liveModeMessage())
    }

    func setLED(at position: GridPosition, color: LaunchpadColor) {
        sendSysEx(LaunchpadProtocol.rgbLEDMessage(
            note: position.midiNote, r: color.r, g: color.g, b: color.b
        ))
    }

    func setLEDPulsing(at position: GridPosition, colorIndex: UInt8) {
        sendSysEx(LaunchpadProtocol.paletteLEDMessage(
            note: position.midiNote, type: 2, colorIndex: colorIndex
        ))
    }

    func clearAllLEDs() {
        var entries: [(note: UInt8, r: UInt8, g: UInt8, b: UInt8)] = []
        for row in 0..<8 {
            for col in 0..<8 {
                let pos = GridPosition(row: row, column: col)
                entries.append((note: pos.midiNote, r: 0, g: 0, b: 0))
            }
        }
        sendSysEx(LaunchpadProtocol.batchRGBMessage(entries: entries))
    }

    func syncLEDs(with project: Project, playingPads: Set<GridPosition>) {
        var entries: [(note: UInt8, r: UInt8, g: UInt8, b: UInt8)] = []
        for pad in project.pads {
            let color = playingPads.contains(pad.position) ? LaunchpadColor.playing : pad.color
            entries.append((note: pad.position.midiNote, r: color.r, g: color.g, b: color.b))
        }
        sendSysEx(LaunchpadProtocol.batchRGBMessage(entries: entries))
    }

    func sendBatchLEDs(entries: [(note: UInt8, r: UInt8, g: UInt8, b: UInt8)]) {
        sendSysEx(LaunchpadProtocol.batchRGBMessage(entries: entries))
    }

    /// Set a side button LED (notes 19, 29, ..., 89).
    func setSideButtonLED(note: UInt8, color: LaunchpadColor) {
        sendSysEx(LaunchpadProtocol.rgbLEDMessage(note: note, r: color.r, g: color.g, b: color.b))
    }

    /// Render XY performance grid: X = pentatonic notes (colored per scale degree), Y = volume (dim→bright).
    /// Cursor position gets a white highlight.
    func renderXYGrid(cursor: GridPosition?) {
        // Colors per pentatonic column: blue→cyan→green→yellow→orange, repeating for octave
        let noteColors: [(r: UInt8, g: UInt8, b: UInt8)] = [
            (0, 20, 127),   // C  — blue
            (0, 80, 127),   // D  — cyan
            (0, 127, 40),   // E  — green
            (100, 127, 0),  // G  — yellow
            (127, 60, 0),   // A  — orange
            (0, 20, 127),   // C' — blue
            (0, 80, 127),   // D' — cyan
            (0, 127, 40),   // E' — green
        ]

        var entries: [(note: UInt8, r: UInt8, g: UInt8, b: UInt8)] = []
        for row in 0..<8 {
            // Y brightness: row 0 = dim (volume low), row 7 = bright (volume high)
            let yBrightness = 0.2 + (Float(row) / 7.0) * 0.8
            for col in 0..<8 {
                let pos = GridPosition(row: row, column: col)
                if pos == cursor {
                    entries.append((note: pos.midiNote, r: 127, g: 127, b: 127))
                    continue
                }
                let base = noteColors[col]
                let r = UInt8(min(127, Float(base.r) * yBrightness))
                let g = UInt8(min(127, Float(base.g) * yBrightness))
                let b = UInt8(min(127, Float(base.b) * yBrightness))
                entries.append((note: pos.midiNote, r: r, g: g, b: b))
            }
        }
        sendSysEx(LaunchpadProtocol.batchRGBMessage(entries: entries))
    }

    // MARK: - Private

    private func setupMIDI(initialScan: Bool) {
        MIDIClientCreateWithBlock("Soundboard" as CFString, &midiClient) { [weak self] notification in
            let messageID = notification.pointee.messageID
            if messageID == .msgSetupChanged {
                DispatchQueue.main.async {
                    self?.scanForDevices()
                }
            }
        }

        MIDIOutputPortCreate(midiClient, "Output" as CFString, &outputPort)

        MIDIInputPortCreateWithProtocol(
            midiClient,
            "Input" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, _ in
            self?.handleMIDIEvents(eventList)
        }

        if initialScan {
            scanForDevices()
        }
    }

    private func handleMIDIEvents(_ eventListPtr: UnsafePointer<MIDIEventList>) {
        let eventList = eventListPtr.pointee
        var packet = eventList.packet

        for _ in 0..<eventList.numPackets {
            let words = Mirror(reflecting: packet.words).children.map { $0.value as! UInt32 }
            guard let firstWord = words.first, firstWord != 0 else {
                packet = MIDIEventPacketNext(&packet).pointee
                continue
            }

            // MIDI 1.0 channel voice message in UMP format
            // Word format: [messageType(4) group(4) status(8) note(8) velocity(8)]
            let messageType = (firstWord >> 28) & 0x0F
            let status = (firstWord >> 16) & 0xFF
            let note = UInt8((firstWord >> 8) & 0xFF)
            let velocity = UInt8(firstWord & 0xFF)

            if messageType == 0x02 { // MIDI 1.0 channel voice
                let statusHigh = status & 0xF0
                if statusHigh == 0x90 && velocity > 0 { // Note On
                    if let position = GridPosition.from(midiNote: note) {
                        DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                            self?.onPadPressed?(position, velocity)
                        }
                    }
                } else if statusHigh == 0x80 || (statusHigh == 0x90 && velocity == 0) { // Note Off
                    if let position = GridPosition.from(midiNote: note) {
                        DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                            self?.onPadReleased?(position)
                        }
                    }
                } else if statusHigh == 0xB0 && velocity > 0 { // Control Change (side/top buttons)
                    DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                        self?.onSideButtonPressed?(note)
                    }
                }
            }

            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    private func sendSysEx(_ data: [UInt8]) {
        guard connectedDestination != 0 else { return }

        let count = data.count
        let dataCopy = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: count)
        _ = dataCopy.initialize(from: data)

        let requestPtr = UnsafeMutablePointer<MIDISysexSendRequest>.allocate(capacity: 1)
        requestPtr.initialize(to: MIDISysexSendRequest(
            destination: connectedDestination,
            data: UnsafePointer(dataCopy.baseAddress!),
            bytesToSend: UInt32(count),
            complete: false,
            reserved: (0, 0, 0),
            completionProc: { ptr in
                // CoreMIDI advances .data during send, so use the original
                // base address saved in completionRefCon
                ptr.pointee.completionRefCon!
                    .assumingMemoryBound(to: UInt8.self)
                    .deallocate()
                ptr.deinitialize(count: 1)
                ptr.deallocate()
            },
            completionRefCon: UnsafeMutableRawPointer(dataCopy.baseAddress!)
        ))

        MIDISendSysex(requestPtr)
    }

    private func getMIDIName(_ endpoint: MIDIEndpointRef) -> String? {
        var name: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
        guard status == noErr, let cfName = name else { return nil }
        return cfName.takeRetainedValue() as String
    }
}
