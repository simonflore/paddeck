import Foundation

struct Sample: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var filename: String
    var trimStart: Double
    var trimEnd: Double?
    var fileDuration: Double

    var effectiveDuration: Double {
        max(0, (trimEnd ?? fileDuration) - trimStart)
    }

    init(name: String, filename: String, fileDuration: Double) {
        self.id = UUID()
        self.name = name
        self.filename = filename
        self.trimStart = 0
        self.trimEnd = nil
        self.fileDuration = fileDuration
    }
}
