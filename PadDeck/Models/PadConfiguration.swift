import Foundation

struct PadConfiguration: Codable, Identifiable, Sendable {
    let position: GridPosition
    var sample: Sample?
    var color: LaunchpadColor
    var playMode: PlayMode
    var volume: Float
    var emoji: String?
    var vocalConfig: VocalPadConfig?
    var instrumentConfig: InstrumentConfig?
    var syncConfig: PadSyncConfig?

    var id: Int { position.id }
    var isEmpty: Bool { sample == nil && vocalConfig == nil && instrumentConfig == nil }
    var isVocalPad: Bool { vocalConfig != nil }
    var isInstrumentPad: Bool { instrumentConfig != nil }
    var isSynced: Bool { syncConfig != nil }

    init(position: GridPosition) {
        self.position = position
        self.sample = nil
        self.color = .off
        self.playMode = .oneShot
        self.volume = 1.0
        self.emoji = nil
        self.vocalConfig = nil
        self.instrumentConfig = nil
        self.syncConfig = nil
    }

    init(position: GridPosition, sample: Sample?, color: LaunchpadColor, playMode: PlayMode, volume: Float, emoji: String? = nil, vocalConfig: VocalPadConfig? = nil, instrumentConfig: InstrumentConfig? = nil, syncConfig: PadSyncConfig? = nil) {
        self.position = position
        self.sample = sample
        self.color = color
        self.playMode = playMode
        self.volume = volume
        self.emoji = emoji
        self.vocalConfig = vocalConfig
        self.instrumentConfig = instrumentConfig
        self.syncConfig = syncConfig
    }
}
