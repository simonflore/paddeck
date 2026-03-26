import Foundation

@Observable
final class ProjectManager {
    private(set) var availableProjects: [ProjectMetadata] = []

    private let projectsDirectory: URL
    private let sampleStore: SampleStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(sampleStore: SampleStore) {
        self.sampleStore = sampleStore
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.projectsDirectory = appSupport
            .appendingPathComponent("Soundboard", isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        scanProjects()
    }

    func save(_ project: Project) throws {
        var proj = project
        proj.modifiedAt = Date()
        let data = try encoder.encode(proj)
        let url = projectURL(for: proj.id)
        try data.write(to: url, options: .atomic)
        UserDefaults.standard.set(proj.id.uuidString, forKey: "lastProjectID")
        scanProjects()
    }

    func load(id: UUID) throws -> Project {
        let url = projectURL(for: id)
        let data = try Data(contentsOf: url)
        return try decoder.decode(Project.self, from: data)
    }

    func loadLastProject() -> Project? {
        guard let idString = UserDefaults.standard.string(forKey: "lastProjectID"),
              let id = UUID(uuidString: idString) else { return nil }
        return try? load(id: id)
    }

    func delete(id: UUID) throws {
        let url = projectURL(for: id)
        try FileManager.default.removeItem(at: url)
        scanProjects()
    }

    func findByName(_ name: String) -> ProjectMetadata? {
        availableProjects.first { $0.name == name }
    }

    // MARK: - Private

    private func projectURL(for id: UUID) -> URL {
        projectsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func scanProjects() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        availableProjects = contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ProjectMetadata? in
                guard let data = try? Data(contentsOf: url),
                      let project = try? decoder.decode(Project.self, from: data) else { return nil }
                return ProjectMetadata(id: project.id, name: project.name, modifiedAt: project.modifiedAt)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }
}

struct ProjectMetadata: Identifiable {
    let id: UUID
    let name: String
    let modifiedAt: Date
}
