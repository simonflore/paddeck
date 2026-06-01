import Foundation
import CoreMIDI

struct ClockSourceInfo: Identifiable, Hashable {
    let id: Int
    let name: String
    let source: MIDIEndpointRef
}

/// Owns its own CoreMIDI input port and connects to a user-selected clock source.
/// Parses only MIDI real-time + transport messages and forwards them to TransportClock.
@Observable
final class ClockReceiver {
    private(set) var availableSources: [ClockSourceInfo] = []
    private(set) var connectedSourceName: String?
    var isConnected: Bool { connectedSource != 0 }

    /// The transport to forward parsed events to.
    @ObservationIgnored weak var transport: TransportClock?
    /// Persisted preferred source name; the receiver reconnects to it when present.
    @ObservationIgnored var preferredSourceName: String?

    @ObservationIgnored private var client: MIDIClientRef = 0
    @ObservationIgnored private var inputPort: MIDIPortRef = 0
    @ObservationIgnored private var connectedSource: MIDIEndpointRef = 0

    init() {
        setup()
    }

    private func setup() {
        MIDIClientCreateWithBlock("PadDeckClock" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.scan() }
            }
        }
        MIDIInputPortCreateWithProtocol(client, "ClockIn" as CFString, ._1_0, &inputPort) { [weak self] eventList, _ in
            self?.handleEvents(eventList)
        }
        scan()
    }

    // MARK: - Device management

    func scan() {
        var sources: [ClockSourceInfo] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            guard let name = name(of: src) else { continue }
            sources.append(ClockSourceInfo(id: Int(src), name: name, source: src))
        }
        availableSources = sources

        // Drop a vanished connection.
        if isConnected && !sources.contains(where: { $0.source == connectedSource }) {
            disconnect()
        }
        // Auto-reconnect to the preferred source by name.
        if !isConnected, let pref = preferredSourceName,
           let match = sources.first(where: { $0.name == pref }) {
            connect(to: match)
        }
    }

    func connect(to info: ClockSourceInfo) {
        disconnect()
        if MIDIPortConnectSource(inputPort, info.source, nil) == noErr {
            connectedSource = info.source
            connectedSourceName = info.name
            preferredSourceName = info.name
        }
    }

    func disconnect() {
        if connectedSource != 0 {
            MIDIPortDisconnectSource(inputPort, connectedSource)
        }
        connectedSource = 0
        connectedSourceName = nil
    }

    // MARK: - MIDI thread parsing (minimal)

    private func handleEvents(_ listPtr: UnsafePointer<MIDIEventList>) {
        let list = listPtr.pointee
        var packet = list.packet
        guard let transport else { return }

        for _ in 0..<list.numPackets {
            let words = Mirror(reflecting: packet.words).children.compactMap { $0.value as? UInt32 }
            if let firstWord = words.first, firstWord != 0 {
                let messageType = (firstWord >> 28) & 0x0F
                // UMP type 0x1 = System Real-Time and System Common.
                if messageType == 0x01 {
                    let status = UInt8((firstWord >> 16) & 0xFF)
                    let data1 = UInt8((firstWord >> 8) & 0xFF)
                    let data2 = UInt8(firstWord & 0xFF)
                    switch status {
                    case 0xF8: transport.handleTick(hostTime: packet.timeStamp)
                    case 0xFA: transport.handleStart()
                    case 0xFB: transport.handleContinue()
                    case 0xFC: transport.handleStop()
                    case 0xF2:
                        let beats = Int(data1) | (Int(data2) << 7) // LSB, MSB
                        transport.handleSPP(beats: beats)
                    default: break // ignore other real-time/common bytes
                    }
                }
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    private func name(of endpoint: MIDIEndpointRef) -> String? {
        var cf: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &cf) == noErr,
              let cf else { return nil }
        return cf.takeRetainedValue() as String
    }
}
