import Foundation
import CoreTransferable
import UniformTypeIdentifiers

struct GridPosition: Hashable, Codable, Identifiable, Sendable {
    let row: Int    // 0-7, bottom to top (matches Launchpad layout)
    let column: Int // 0-7, left to right

    var id: Int { row * 8 + column }

    /// Launchpad programmer mode note number (all supported models).
    /// Row 0 (bottom) = notes 11-18, row 7 (top) = notes 81-88.
    var midiNote: UInt8 {
        UInt8((row + 1) * 10 + (column + 1))
    }

    /// Create from a Launchpad programmer mode note number.
    static func from(midiNote: UInt8) -> GridPosition? {
        let note = Int(midiNote)
        let row = (note / 10) - 1
        let col = (note % 10) - 1
        guard (0...7).contains(row), (0...7).contains(col) else { return nil }
        return GridPosition(row: row, column: col)
    }
}

extension GridPosition: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
