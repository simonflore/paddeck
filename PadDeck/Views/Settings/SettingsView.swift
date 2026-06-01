import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var newProjectName = ""
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isImportPickerPresented = false

    var body: some View {
        TabView {
            midiTab
                .tabItem { Label("MIDI", systemImage: "pianokeys") }

            audioTab
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }

            projectsTab
                .tabItem { Label("Projects", systemImage: "folder") }
        }
        #if os(macOS)
        .frame(width: 450, height: 350)
        #endif
    }

    // MARK: - Audio Tab

    private var audioTab: some View {
        Form {
            Section("Microphone") {
                HStack(spacing: 8) {
                    Image(systemName: micGainIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Slider(
                        value: Binding(
                            get: { appState.micGain },
                            set: { appState.micGain = $0 }
                        ),
                        in: 0...2,
                        step: 0.05
                    )

                    Text("\(Int(appState.micGain * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                Text("Adjusts microphone input gain for live vocal pads.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            #if os(iOS)
            Section("Playback") {
                Toggle(isOn: Binding(
                    get: { appState.duckExternalAudio },
                    set: { appState.duckExternalAudio = $0 }
                )) {
                    Text("Duck External Audio")
                }

                Text("Lowers other apps' audio while PadDeck is playing.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            #endif
        }
        .formStyle(.grouped)
    }

    private var micGainIcon: String {
        if appState.micGain == 0 { return "mic.slash" }
        if appState.micGain < 0.5 { return "mic" }
        return "mic.fill"
    }

    // MARK: - MIDI Tab

    private var midiTab: some View {
        Form {
            Section("Launchpad Connection") {
                HStack {
                    Circle()
                        .fill(appState.midiManager.isConnected ? .green : .red)
                        .frame(width: 10, height: 10)
                    Text(appState.midiManager.isConnected ? appState.midiManager.deviceName : "Not Connected")
                }

                if !appState.midiManager.availableDevices.isEmpty {
                    ForEach(appState.midiManager.availableDevices) { device in
                        HStack {
                            Text(device.name)
                            Spacer()
                            if appState.midiManager.connectedDeviceID == device.id {
                                Text("Connected")
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Connect") {
                                    appState.midiManager.connect(to: device)
                                    appState.midiManager.onDeviceConnected?()
                                }
                            }
                        }
                    }
                }

                Button("Scan for Devices") {
                    appState.midiManager.scanForDevices()
                }
            }

            Section("MIDI Clock") {
                Picker("Clock Source", selection: Binding(
                    get: { appState.transportSettings.clockSourceName ?? "" },
                    set: { name in
                        appState.transportSettings.clockSourceName = name.isEmpty ? nil : name
                        appState.clockReceiver.preferredSourceName = name.isEmpty ? nil : name
                        if name.isEmpty {
                            appState.clockReceiver.disconnect()
                        } else if let src = appState.clockReceiver.availableSources.first(where: { $0.name == name }) {
                            appState.clockReceiver.connect(to: src)
                        }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(appState.clockReceiver.availableSources) { src in
                        Text(src.name).tag(src.name)
                    }
                }

                Toggle("Follow External Clock", isOn: Binding(
                    get: { appState.transportSettings.followExternalClock },
                    set: { appState.transportSettings.followExternalClock = $0 }
                ))

                // Time signature (default 4/4).
                Stepper(value: Binding(
                    get: { appState.transportSettings.timeSignature.beatsPerBar },
                    set: { appState.transportSettings.timeSignature.beatsPerBar = max(1, $0) }
                ), in: 1...16) {
                    Text("Beats per Bar: \(appState.transportSettings.timeSignature.beatsPerBar)")
                }
                Picker("Beat Unit", selection: Binding(
                    get: { appState.transportSettings.timeSignature.beatUnit },
                    set: { appState.transportSettings.timeSignature.beatUnit = $0 }
                )) {
                    ForEach([2, 4, 8, 16], id: \.self) { unit in
                        Text("1/\(unit)").tag(unit)
                    }
                }

                Toggle("Ignore Start/Stop", isOn: Binding(
                    get: { appState.transportSettings.ignoreStartStop },
                    set: { appState.transportSettings.ignoreStartStop = $0 }
                ))

                Toggle("Stop Synced Loops Immediately", isOn: Binding(
                    get: { appState.transportSettings.stopImmediately },
                    set: { appState.transportSettings.stopImmediately = $0 }
                ))

                HStack {
                    Text("Latency Offset")
                    Slider(value: Binding(
                        get: { appState.transportSettings.latencyOffsetMs },
                        set: { appState.transportSettings.latencyOffsetMs = $0 }
                    ), in: -50...50, step: 1)
                    Text("\(Int(appState.transportSettings.latencyOffsetMs)) ms")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }

                Button("Rescan MIDI Sources") {
                    appState.clockReceiver.scan()
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Projects Tab

    private var projectsTab: some View {
        Form {
            Section("Current Project") {
                HStack {
                    Text(appState.project.name)
                        .font(.headline)
                    Spacer()
                    Text("\(appState.project.pads.filter { !$0.isEmpty }.count) samples loaded")
                        .foregroundStyle(.secondary)
                }
            }

            Section("New Project") {
                HStack {
                    TextField("Project Name", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)

                    Button("Create") {
                        guard !newProjectName.isEmpty else { return }
                        let newProject = Project(name: newProjectName)
                        try? appState.projectManager.save(newProject)
                        appState.switchProject(newProject)
                        newProjectName = ""
                    }
                    .disabled(newProjectName.isEmpty)
                }
            }

            Section("Saved Projects") {
                let projects = appState.projectManager.availableProjects
                if projects.isEmpty {
                    Text("No saved projects")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projects) { meta in
                        HStack {
                            Text(meta.name)
                            Spacer()
                            if meta.id == appState.project.id {
                                Text("Active")
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Load") {
                                    if let loaded = try? appState.projectManager.load(id: meta.id) {
                                        appState.switchProject(loaded)
                                    }
                                }
                            }

                            Button {
                                exportProject(meta)
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("Import") {
                Button {
                    isImportPickerPresented = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import .paddeck File")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileExporter(
            isPresented: $isExporting,
            document: PadDeckExportDocument(url: exportURL),
            contentType: PadDeckBundle.projectType,
            defaultFilename: exportURL?.deletingPathExtension().lastPathComponent ?? "Project"
        ) { result in
            // Clean up temp file after export
            if let url = exportURL {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
            exportURL = nil
        }
        .fileImporter(
            isPresented: $isImportPickerPresented,
            allowedContentTypes: [PadDeckBundle.projectType, .zip],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            appState.handleOpenURL(url)
        }
    }

    private func exportProject(_ meta: ProjectMetadata) {
        guard let project = try? appState.projectManager.load(id: meta.id) else { return }
        guard let url = try? PadDeckBundle.export(project: project, sampleStore: appState.sampleStore) else { return }
        exportURL = url
        isExporting = true
    }
}

/// Wrapper for `.fileExporter` — reads the temp ZIP file as raw data.
struct PadDeckExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [PadDeckBundle.projectType] }

    let data: Data

    init(url: URL?) {
        self.data = (try? Data(contentsOf: url ?? URL(fileURLWithPath: ""))) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
