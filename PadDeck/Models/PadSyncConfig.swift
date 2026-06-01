import Foundation

/// Per-pad synced-loop settings. Presence on a PadConfiguration marks it "Synced".
struct PadSyncConfig: Codable, Sendable, Equatable {
    /// Declared musical length of the loop file (used for phase-lock + mismatch warning).
    var loopLength: MusicalLength
    /// Overrides the global launch quantization when non-nil.
    var quantizeOverride: Quantization?
    /// Phase 2 scaffold — inert in Phase 1.
    var timeStretchEnabled: Bool

    init(loopLength: MusicalLength = MusicalLength(bars: 1, beats: 0),
         quantizeOverride: Quantization? = nil,
         timeStretchEnabled: Bool = false) {
        self.loopLength = loopLength
        self.quantizeOverride = quantizeOverride
        self.timeStretchEnabled = timeStretchEnabled
    }
}
