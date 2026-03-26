import UniformTypeIdentifiers

enum AudioFormats {
    static let supportedTypes: [UTType] = [
        .wav, .mp3, .aiff, .mpeg4Audio,
    ]

    static let supportedExtensions: Set<String> = {
        var exts = Set<String>()
        for type in supportedTypes {
            if let tags = type.tags[.filenameExtension] {
                exts.formUnion(tags)
            }
        }
        // Include common aliases not covered by UTType tags
        exts.insert("aif")
        return exts
    }()

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
