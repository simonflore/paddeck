import Foundation

struct Project: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var pads: [PadConfiguration]
    var createdAt: Date
    var modifiedAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.pads = (0..<8).flatMap { row in
            (0..<8).map { col in
                PadConfiguration(position: GridPosition(row: row, column: col))
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        var decoded = try container.decode([PadConfiguration].self, forKey: .pads)
        // Ensure exactly 64 pads — fill missing entries with defaults
        if decoded.count < 64 {
            for row in 0..<8 {
                for col in 0..<8 {
                    let pos = GridPosition(row: row, column: col)
                    if pos.id >= decoded.count {
                        decoded.append(PadConfiguration(position: pos))
                    }
                }
            }
        }
        self.pads = Array(decoded.prefix(64))
    }

    func pad(at position: GridPosition) -> PadConfiguration {
        pads[position.id]
    }

    mutating func setPad(_ config: PadConfiguration, at position: GridPosition) {
        pads[position.id] = config
        modifiedAt = Date()
    }

    func emptyPadsInVisualOrder() -> [GridPosition] {
        (0..<8).reversed().flatMap { row in
            (0..<8).compactMap { col in
                let pos = GridPosition(row: row, column: col)
                return pad(at: pos).isEmpty ? pos : nil
            }
        }
    }

    mutating func swapPads(_ a: GridPosition, _ b: GridPosition) {
        guard a != b else { return }
        let padA = pads[a.id]
        let padB = pads[b.id]
        // Swap contents (sample, color, playMode, volume) but keep positions fixed
        pads[a.id] = PadConfiguration(position: a, sample: padB.sample, color: padB.color, playMode: padB.playMode, volume: padB.volume, emoji: padB.emoji)
        pads[b.id] = PadConfiguration(position: b, sample: padA.sample, color: padA.color, playMode: padA.playMode, volume: padA.volume, emoji: padA.emoji)
        modifiedAt = Date()
    }
}
