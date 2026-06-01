import Foundation

/// App-global transport/clock settings, persisted as JSON in UserDefaults.
struct TransportSettings: Codable, Sendable, Equatable {
    var globalQuantize: Quantization = .bar
    var timeSignature: TimeSignature = TimeSignature()
    var followExternalClock: Bool = true
    var ignoreStartStop: Bool = false
    var stopImmediately: Bool = false
    var latencyOffsetMs: Double = 0
    var manualBPM: Double = 120
    var clockSourceName: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TransportSettings()
        globalQuantize = try c.decodeIfPresent(Quantization.self, forKey: .globalQuantize) ?? d.globalQuantize
        timeSignature = try c.decodeIfPresent(TimeSignature.self, forKey: .timeSignature) ?? d.timeSignature
        followExternalClock = try c.decodeIfPresent(Bool.self, forKey: .followExternalClock) ?? d.followExternalClock
        ignoreStartStop = try c.decodeIfPresent(Bool.self, forKey: .ignoreStartStop) ?? d.ignoreStartStop
        stopImmediately = try c.decodeIfPresent(Bool.self, forKey: .stopImmediately) ?? d.stopImmediately
        latencyOffsetMs = try c.decodeIfPresent(Double.self, forKey: .latencyOffsetMs) ?? d.latencyOffsetMs
        manualBPM = try c.decodeIfPresent(Double.self, forKey: .manualBPM) ?? d.manualBPM
        clockSourceName = try c.decodeIfPresent(String.self, forKey: .clockSourceName)
    }

    private static let key = "transportSettings"

    static func load() -> TransportSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(TransportSettings.self, from: data)
        else { return TransportSettings() }
        return s
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
