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
    private(set) var detectedModel: LaunchpadModel?
    private(set) var availableDevices: [MIDIDeviceInfo] = []
    /// `MIDIDeviceInfo.id` of the currently-connected device, or nil.
    var connectedDeviceID: Int? { connectedSource != 0 ? Int(connectedSource) : nil }

    private var lpProtocol: LaunchpadProtocol?
    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    private var inputPort: MIDIPortRef = 0
    private var connectedSource: MIDIEndpointRef = 0
    private var connectedDestination: MIDIEndpointRef = 0

    var onPadPressed: ((GridPosition, UInt8) -> Void)?
    var onPadReleased: ((GridPosition) -> Void)?
    /// Called with the logical side button index (0 = bottom, 7 = top).
    var onSideButtonPressed: ((Int) -> Void)?
    /// Called with the logical top button index (0 = left, 7 = right).
    var onTopButtonPressed: ((Int) -> Void)?
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
            let isLaunchpad = LaunchpadModel.detect(from: name) != nil
            #if DEBUG
            print("[MIDI]   source[\(i)]: \"\(name)\" (match: \(isLaunchpad))")
            #endif
            guard isLaunchpad else { continue }

            // Pair source with destination by matching port type (MIDI↔MIDI, DAW↔DAW).
            let portType = portSuffix(name)
            if let dest = destMap.first(where: { LaunchpadModel.detect(from: $0.key) != nil && portSuffix($0.key) == portType })?.value {
                devices.append(MIDIDeviceInfo(
                    id: Int(source),
                    name: name,
                    source: source,
                    destination: dest
                ))
            }
        }

        // Prefer DAW port — side/top buttons only send on DAW in programmer mode.
        devices.sort { a, b in
            let aIsDAW = a.name.lowercased().contains("daw")
            let bIsDAW = b.name.lowercased().contains("daw")
            return aIsDAW && !bIsDAW
        }

        availableDevices = devices

        if isConnected && !devices.contains(where: { $0.source == connectedSource }) {
            disconnect()
        }

        if !isConnected, let device = devices.first {
            connect(to: device)
            onDeviceConnected?()
        }
    }

    /// "daw" or "midi" so matching source/destination ports get paired.
    private func portSuffix(_ name: String) -> String {
        name.lowercased().contains("daw") ? "daw" : "midi"
    }

    func connect(to device: MIDIDeviceInfo) {
        disconnect()

        connectedSource = device.source
        connectedDestination = device.destination

        let model = LaunchpadModel.detect(from: device.name)
        detectedModel = model
        lpProtocol = model.map { LaunchpadProtocol(model: $0) }

        let status = MIDIPortConnectSource(inputPort, connectedSource, nil)
        if status == noErr {
            isConnected = true
            deviceName = model?.displayName ?? device.name
            #if DEBUG
            print("[MIDI] Connected: \(deviceName) (model: \(model?.rawValue ?? "unknown"))")
            #endif
        }
    }

    func disconnect() {
        if connectedSource != 0 {
            MIDIPortDisconnectSource(inputPort, connectedSource)
        }
        isConnected = false
        deviceName = "No device"
        detectedModel = nil
        lpProtocol = nil
        connectedSource = 0
        connectedDestination = 0
    }

    func enterProgrammerMode() {
        guard let proto = lpProtocol else { return }
        send(proto.programmerModeMessages())
    }

    func exitProgrammerMode() {
        guard let proto = lpProtocol else { return }
        send(proto.liveModeMessages())
    }

    func setLED(at position: GridPosition, color: LaunchpadColor) {
        guard let proto = lpProtocol else { return }
        let note = proto.gridNote(for: position)
        send(proto.ledMessages(note: note, r: color.r, g: color.g, b: color.b))
    }

    func setLEDPulsing(at position: GridPosition, colorIndex: UInt8) {
        guard let proto = lpProtocol else { return }
        let note = proto.gridNote(for: position)
        send(proto.pulsingLEDMessages(note: note, colorIndex: colorIndex))
    }

    func clearAllLEDs() {
        guard let proto = lpProtocol else { return }
        var entries: [(note: UInt8, r: UInt8, g: UInt8, b: UInt8)] = []
        for row in 0..<8 {
            for col in 0..<8 {
                let pos = GridPosition(row: row, column: col)
                entries.append((note: proto.gridNote(for: pos), r: 0, g: 0, b: 0))
            }
        }
        send(proto.batchLEDMessages(entries: entries))
    }

    func syncLEDs(with project: Project, playingPads: Set<GridPosition>) {
        guard let proto = lpProtocol else { return }
        var entries: [(note: UInt8, r: UInt8, g: UInt8, b: UInt8)] = []
        for pad in project.pads {
            let color = playingPads.contains(pad.position) ? LaunchpadColor.playing : pad.color
            entries.append((
                note: proto.gridNote(for: pad.position),
                r: color.r, g: color.g, b: color.b
            ))
        }
        send(proto.batchLEDMessages(entries: entries))
    }

    /// Batch set grid LEDs from positions + colors. Callers don't need to know
    /// per-model note mapping.
    func sendBatchLEDs(_ items: [(position: GridPosition, color: LaunchpadColor)]) {
        guard let proto = lpProtocol else { return }
        let entries = items.map {
            (note: proto.gridNote(for: $0.position),
             r: $0.color.r, g: $0.color.g, b: $0.color.b)
        }
        send(proto.batchLEDMessages(entries: entries))
    }

    /// Set a side button LED by logical index (0 = bottom, 7 = top).
    func setSideButtonLED(index: Int, color: LaunchpadColor) {
        guard let proto = lpProtocol, (0...7).contains(index) else { return }
        let note = proto.sideButtonNote(for: index)
        send(proto.ledMessages(note: note, r: color.r, g: color.g, b: color.b))
    }

    /// Set a top-row button LED by logical index (0 = left, 7 = right).
    func setTopButtonLED(index: Int, color: LaunchpadColor) {
        guard let proto = lpProtocol, (0...7).contains(index) else { return }
        let cc = proto.topButtonCC(for: index)
        send(proto.topButtonLEDMessages(cc: cc, r: color.r, g: color.g, b: color.b))
    }

    // MARK: - Private

    private func setupMIDI(initialScan: Bool) {
        MIDIClientCreateWithBlock("PadDeck" as CFString, &midiClient) { [weak self] notification in
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
        guard let proto = lpProtocol else { return }

        for _ in 0..<eventList.numPackets {
            let words = Mirror(reflecting: packet.words).children.compactMap { $0.value as? UInt32 }
            guard let firstWord = words.first, firstWord != 0 else {
                packet = MIDIEventPacketNext(&packet).pointee
                continue
            }

            // UMP MIDI 1.0 channel voice format:
            // [messageType(4) group(4) status(8) data1(8) data2(8)]
            let messageType = (firstWord >> 28) & 0x0F
            let status = (firstWord >> 16) & 0xFF
            let data1 = UInt8((firstWord >> 8) & 0xFF)
            let data2 = UInt8(firstWord & 0xFF)

            if messageType == 0x02 {
                let statusHigh = status & 0xF0
                if statusHigh == 0x90 && data2 > 0 { // Note On
                    if let position = proto.gridPosition(for: data1) {
                        DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                            self?.onPadPressed?(position, data2)
                        }
                    } else if let index = proto.sideButtonIndex(for: data1) {
                        DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                            self?.onSideButtonPressed?(index)
                        }
                    }
                } else if statusHigh == 0x80 || (statusHigh == 0x90 && data2 == 0) { // Note Off
                    if let position = proto.gridPosition(for: data1) {
                        DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                            self?.onPadReleased?(position)
                        }
                    }
                } else if statusHigh == 0xB0 { // Control Change
                    // Top-row buttons: CC 91–98 (programmer) or 104–111 (legacy).
                    if data2 > 0, let index = proto.topButtonIndex(for: data1) {
                        DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                            self?.onTopButtonPressed?(index)
                        }
                    }
                    // Side buttons on the DAW port of programmer-mode devices echo
                    // as CC 19, 29, …, 89. Legacy Mini never uses this path.
                    else if data2 > 0, let index = proto.sideButtonIndex(for: data1) {
                        DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                            self?.onSideButtonPressed?(index)
                        }
                    }
                }
            }

            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    // MARK: - Send

    private func send(_ messages: [LaunchpadProtocol.MIDIMessage]) {
        for msg in messages {
            switch msg {
            case .sysEx(let bytes):
                sendSysEx(bytes)
            case .short(let s, let d1, let d2):
                sendShortMessage(status: s, data1: d1, data2: d2)
            }
        }
    }

    private func sendSysEx(_ data: [UInt8]) {
        guard connectedDestination != 0, outputPort != 0 else { return }

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
                ptr.pointee.completionRefCon!
                    .assumingMemoryBound(to: UInt8.self)
                    .deallocate()
                ptr.deinitialize(count: 1)
                ptr.deallocate()
            },
            completionRefCon: UnsafeMutableRawPointer(dataCopy.baseAddress!)
        ))

        let status = MIDISendSysex(requestPtr)
        if status != noErr {
            dataCopy.deallocate()
            requestPtr.deinitialize(count: 1)
            requestPtr.deallocate()
        }
    }

    private func sendShortMessage(status: UInt8, data1: UInt8, data2: UInt8) {
        guard connectedDestination != 0, outputPort != 0 else { return }

        // UMP MIDI 1.0 channel voice: type 0x2, group 0.
        var word: UInt32 = (UInt32(0x2) << 28)
            | (UInt32(status) << 16)
            | (UInt32(data1) << 8)
            | UInt32(data2)

        var eventList = MIDIEventList()
        let packetPtr = MIDIEventListInit(&eventList, ._1_0)
        _ = MIDIEventListAdd(&eventList, MemoryLayout<MIDIEventList>.size, packetPtr, 0, 1, &word)
        MIDISendEventList(outputPort, connectedDestination, &eventList)
    }

    private func getMIDIName(_ endpoint: MIDIEndpointRef) -> String? {
        var name: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
        guard status == noErr, let cfName = name else { return nil }
        return cfName.takeRetainedValue() as String
    }
}
