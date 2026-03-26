import Foundation

/// 5-row pixel font for rendering text on the Launchpad 8x8 LED grid.
/// Each glyph is an array of columns, where each column is [Bool] of 8 rows
/// (only the top 5 are used for characters, centered vertically).
enum PixelFont {
    /// Get the glyph columns for a character. Returns 3-5 columns of 8 bools each.
    static func glyph(for char: Character) -> [[Bool]] {
        let pattern = glyphPatterns[char] ?? glyphPatterns["?"] ?? [[false, false, false, false, false]]
        return pattern.map { col in
            // Center the 5-row glyph in the 8-row grid (offset by 1 from top)
            var column = Array(repeating: false, count: 8)
            for (i, bit) in col.enumerated() {
                column[i + 1] = bit // Start at row 1 (leave row 0 empty)
            }
            return column
        }
    }

    // Each glyph is defined as columns of 5 bools (top to bottom).
    // Width varies: most letters are 3 columns, some are 4-5.
    private static let glyphPatterns: [Character: [[Bool]]] = [
        "A": [
            [false, true, true, true, true],
            [true, false, true, false, false],
            [false, true, true, true, true],
        ],
        "B": [
            [true, true, true, true, true],
            [true, false, true, false, true],
            [false, true, false, true, false],
        ],
        "C": [
            [false, true, true, true, false],
            [true, false, false, false, true],
            [true, false, false, false, true],
        ],
        "D": [
            [true, true, true, true, true],
            [true, false, false, false, true],
            [false, true, true, true, false],
        ],
        "E": [
            [true, true, true, true, true],
            [true, false, true, false, true],
            [true, false, false, false, true],
        ],
        "F": [
            [true, true, true, true, true],
            [true, false, true, false, false],
            [true, false, false, false, false],
        ],
        "G": [
            [false, true, true, true, false],
            [true, false, false, false, true],
            [false, false, true, false, true],
        ],
        "H": [
            [true, true, true, true, true],
            [false, false, true, false, false],
            [true, true, true, true, true],
        ],
        "I": [
            [true, false, false, false, true],
            [true, true, true, true, true],
            [true, false, false, false, true],
        ],
        "J": [
            [false, false, false, true, false],
            [false, false, false, false, true],
            [true, true, true, true, true],
        ],
        "K": [
            [true, true, true, true, true],
            [false, false, true, false, false],
            [false, true, false, true, true],
        ],
        "L": [
            [true, true, true, true, true],
            [false, false, false, false, true],
            [false, false, false, false, true],
        ],
        "M": [
            [true, true, true, true, true],
            [false, true, false, false, false],
            [false, false, true, false, false],
            [false, true, false, false, false],
            [true, true, true, true, true],
        ],
        "N": [
            [true, true, true, true, true],
            [false, true, false, false, false],
            [false, false, true, false, false],
            [true, true, true, true, true],
        ],
        "O": [
            [false, true, true, true, false],
            [true, false, false, false, true],
            [false, true, true, true, false],
        ],
        "P": [
            [true, true, true, true, true],
            [true, false, true, false, false],
            [false, true, false, false, false],
        ],
        "Q": [
            [false, true, true, true, false],
            [true, false, false, true, true],
            [false, true, true, true, true],
        ],
        "R": [
            [true, true, true, true, true],
            [true, false, true, false, false],
            [false, true, false, true, true],
        ],
        "S": [
            [false, true, false, false, true],
            [true, false, true, false, true],
            [true, false, false, true, false],
        ],
        "T": [
            [true, false, false, false, false],
            [true, true, true, true, true],
            [true, false, false, false, false],
        ],
        "U": [
            [true, true, true, true, false],
            [false, false, false, false, true],
            [true, true, true, true, false],
        ],
        "V": [
            [true, true, true, false, false],
            [false, false, false, true, true],
            [true, true, true, false, false],
        ],
        "W": [
            [true, true, true, true, true],
            [false, false, false, true, false],
            [false, false, true, false, false],
            [false, false, false, true, false],
            [true, true, true, true, true],
        ],
        "X": [
            [true, true, false, true, true],
            [false, false, true, false, false],
            [true, true, false, true, true],
        ],
        "Y": [
            [true, true, false, false, false],
            [false, false, true, true, true],
            [true, true, false, false, false],
        ],
        "Z": [
            [true, false, false, true, true],
            [true, false, true, false, true],
            [true, true, false, false, true],
        ],
        "0": [
            [false, true, true, true, false],
            [true, false, false, false, true],
            [false, true, true, true, false],
        ],
        "1": [
            [false, true, false, false, false],
            [true, true, true, true, true],
            [false, false, false, false, false],
        ],
        "2": [
            [false, true, false, true, true],
            [true, false, true, false, true],
            [false, true, false, false, true],
        ],
        "3": [
            [true, false, false, false, true],
            [true, false, true, false, true],
            [false, true, false, true, false],
        ],
        "4": [
            [true, true, true, false, false],
            [false, false, true, false, false],
            [true, true, true, true, true],
        ],
        "5": [
            [true, true, false, false, true],
            [true, false, true, false, true],
            [true, false, false, true, false],
        ],
        "6": [
            [false, true, true, true, false],
            [true, false, true, false, true],
            [false, false, false, true, false],
        ],
        "7": [
            [true, false, false, false, false],
            [true, false, false, true, true],
            [true, true, true, false, false],
        ],
        "8": [
            [false, true, false, true, false],
            [true, false, true, false, true],
            [false, true, false, true, false],
        ],
        "9": [
            [false, true, false, false, false],
            [true, false, true, false, true],
            [false, true, true, true, false],
        ],
        " ": [
            [false, false, false, false, false],
            [false, false, false, false, false],
        ],
        "!": [
            [true, true, true, false, true],
        ],
        "-": [
            [false, false, true, false, false],
            [false, false, true, false, false],
        ],
        ".": [
            [false, false, false, false, true],
        ],
        "?": [
            [true, false, false, false, false],
            [true, false, true, false, true],
            [false, true, false, false, false],
        ],
    ]
}
