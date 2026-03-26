import Foundation
import ZIPFoundation
import UniformTypeIdentifiers

enum PadDeckBundle {

    /// Custom UTType for `.paddeck` project bundles.
    static let projectType = UTType("com.paddeck.project")!

    enum BundleError: LocalizedError {
        case couldNotOpenFile
        case invalidBundle
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .couldNotOpenFile:
                return "Could not open project file."
            case .invalidBundle:
                return "This file doesn't contain a valid PadDeck project."
            case .exportFailed(let reason):
                return "Export failed: \(reason)"
            }
        }
    }

    // MARK: - Export

    /// Creates a `.paddeck` ZIP bundle in a temp directory and returns its URL.
    /// Caller is responsible for cleanup after sharing completes.
    static func export(project: Project, sampleStore: SampleStore) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("paddeck-export-\(UUID().uuidString)", isDirectory: true)
        let stageDir = tempDir.appendingPathComponent("stage", isDirectory: true)
        let audioDir = stageDir.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        // Write project.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let projectData = try encoder.encode(project)
        try projectData.write(to: stageDir.appendingPathComponent("project.json"))

        // Copy referenced audio files
        let filenames = referencedFilenames(in: project)
        for filename in filenames {
            let sourceURL = sampleStore.audioDirectory.appendingPathComponent(filename)
            let destURL = audioDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        }

        // Create ZIP
        let safeName = project.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let zipURL = tempDir.appendingPathComponent("\(safeName).paddeck")
        try FileManager.default.zipItem(at: stageDir, to: zipURL)

        // Clean up staging directory (keep the ZIP)
        try? FileManager.default.removeItem(at: stageDir)

        return zipURL
    }

    // MARK: - Import

    /// Result of reading a bundle, before the user decides how to handle duplicates.
    struct ImportPreview {
        let project: Project
        let audioDirectory: URL
        let tempDirectory: URL
        let existingProject: ProjectMetadata?
    }

    /// Reads a `.paddeck` bundle and returns a preview (project + temp audio dir).
    /// Does NOT copy files or save the project — call `finalizeImport` after user confirms.
    static func previewImport(
        from url: URL,
        projectManager: ProjectManager
    ) throws -> ImportPreview {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("paddeck-import-\(UUID().uuidString)", isDirectory: true)

        // Unzip
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try FileManager.default.unzipItem(at: url, to: tempDir)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw BundleError.couldNotOpenFile
        }

        // Find project.json (may be nested in a subdirectory from the ZIP structure)
        guard let projectJsonURL = findProjectJSON(in: tempDir) else {
            try? FileManager.default.removeItem(at: tempDir)
            throw BundleError.invalidBundle
        }

        // Decode project
        let data = try Data(contentsOf: projectJsonURL)
        let project: Project
        do {
            project = try JSONDecoder().decode(Project.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw BundleError.invalidBundle
        }

        let audioDir = projectJsonURL.deletingLastPathComponent()
            .appendingPathComponent("audio", isDirectory: true)

        let existing = projectManager.findByName(project.name)

        return ImportPreview(
            project: project,
            audioDirectory: audioDir,
            tempDirectory: tempDir,
            existingProject: existing
        )
    }

    enum ImportMode {
        case replace(existingID: UUID)
        case keepBoth
        case createNew
    }

    /// Copies audio files and saves the project. Call after user confirms.
    static func finalizeImport(
        preview: ImportPreview,
        mode: ImportMode,
        sampleStore: SampleStore,
        projectManager: ProjectManager
    ) throws -> Project {
        var project = preview.project

        switch mode {
        case .replace(let existingID):
            // Delete the old project, reuse the imported project's data but with the old ID
            try? projectManager.delete(id: existingID)
        case .keepBoth:
            // New UUID + " Copy" suffix
            project = Project.copyForImport(from: project, newName: project.name + " Copy")
        case .createNew:
            break
        }

        // Copy audio files, skipping duplicates (same filename + same size)
        if FileManager.default.fileExists(atPath: preview.audioDirectory.path) {
            let audioFiles = (try? FileManager.default.contentsOfDirectory(
                at: preview.audioDirectory,
                includingPropertiesForKeys: [.fileSizeKey]
            )) ?? []

            for sourceFile in audioFiles {
                let destFile = sampleStore.audioDirectory.appendingPathComponent(sourceFile.lastPathComponent)
                if FileManager.default.fileExists(atPath: destFile.path) {
                    // Skip if same size (likely identical)
                    let sourceSize = (try? sourceFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                    let destSize = (try? destFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
                    if sourceSize == destSize { continue }
                }
                try? FileManager.default.copyItem(at: sourceFile, to: destFile)
            }
        }

        try projectManager.save(project)

        // Clean up temp directory
        try? FileManager.default.removeItem(at: preview.tempDirectory)

        return project
    }

    // MARK: - Helpers

    /// Collects all unique audio filenames referenced by pad configurations.
    private static func referencedFilenames(in project: Project) -> Set<String> {
        var filenames = Set<String>()
        for pad in project.pads {
            if let sample = pad.sample {
                filenames.insert(sample.filename)
            }
        }
        return filenames
    }

    /// Searches for project.json inside the unzipped directory (handles nested ZIP structure).
    private static func findProjectJSON(in directory: URL) -> URL? {
        // Direct child
        let direct = directory.appendingPathComponent("project.json")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        // One level nested (ZIP may wrap in a subdirectory)
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for item in contents {
                let nested = item.appendingPathComponent("project.json")
                if FileManager.default.fileExists(atPath: nested.path) { return nested }
            }
        }
        return nil
    }
}
