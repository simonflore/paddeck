import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var newProjectName = ""

    var body: some View {
        TabView {
            midiTab
                .tabItem { Label("MIDI", systemImage: "pianokeys") }

            audioTab
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }

            projectsTab
                .tabItem { Label("Projects", systemImage: "folder") }
        }
        .frame(width: 450, height: 350)
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
                            if appState.midiManager.deviceName == device.name && appState.midiManager.isConnected {
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
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
