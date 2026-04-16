import Foundation

/// Scrolls text across the Launchpad 8x8 LED grid as a billboard.
@Observable
final class TextScroller {
    private var scrollTask: Task<Void, Error>?
    private weak var midiManager: MIDIManager?
    var textColor: LaunchpadColor = LaunchpadColor(r: 127, g: 127, b: 127)

    init(midiManager: MIDIManager) {
        self.midiManager = midiManager
    }

    /// Scroll a text across the Launchpad grid, then restore pad colors.
    func scrollText(
        _ text: String,
        project: Project,
        activePads: @escaping () -> Set<GridPosition>,
        restoreColors: @escaping () -> Void
    ) {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            let columns = renderTextColumns(text.uppercased())
            let totalFrames = columns.count + 8

            do {
                for frame in 0..<totalFrames {
                    try Task.checkCancellation()

                    let active = activePads()
                    var entries: [(position: GridPosition, color: LaunchpadColor)] = []
                    for row in 0..<8 {
                        for col in 0..<8 {
                            let sourceCol = frame + col
                            let isLit = sourceCol < columns.count && row < columns[sourceCol].count && columns[sourceCol][row]
                            let pos = GridPosition(row: 7 - row, column: col)
                            let color: LaunchpadColor
                            if isLit {
                                color = textColor
                            } else if active.contains(pos) {
                                color = project.pad(at: pos).color
                            } else {
                                let c = project.pad(at: pos).color
                                color = LaunchpadColor(r: c.r / 4, g: c.g / 4, b: c.b / 4)
                            }
                            entries.append((position: pos, color: color))
                        }
                    }

                    midiManager?.sendBatchLEDs(entries)

                    try await Task.sleep(for: .milliseconds(80))
                }

                // Wait for the last SysEx to deliver before restoring
                try await Task.sleep(for: .milliseconds(100))
            } catch {}

            if !Task.isCancelled {
                restoreColors()
            }
        }
    }

    func cancel() {
        scrollTask?.cancel()
    }

    // MARK: - Text Rendering

    /// Render text into vertical columns of booleans (8 rows high).
    /// Each character is 3-5 columns wide with 1 column spacing.
    private func renderTextColumns(_ text: String) -> [[Bool]] {
        var columns: [[Bool]] = []

        // 8 columns padding so text enters from the right edge
        for _ in 0..<8 {
            columns.append(Array(repeating: false, count: 8))
        }

        for char in text {
            let glyph = PixelFont.glyph(for: char)
            for col in glyph {
                columns.append(col)
            }
            // 1 column spacing between characters
            columns.append(Array(repeating: false, count: 8))
        }

        return columns
    }
}
