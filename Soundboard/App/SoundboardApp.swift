import SwiftUI

@main
struct SoundboardApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    appState.setupMIDICallbacks()
                    appState.connectLaunchpad()

                    #if os(macOS)
                    // Force dark appearance for the neon arena aesthetic
                    if let window = NSApplication.shared.windows.first {
                        window.appearance = NSAppearance(named: .darkAqua)
                        window.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1.0)
                        window.titlebarAppearsTransparent = true
                    }
                    #endif
                }
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.pathExtension == "soundboard" else { return }
                    appState.handleOpenURL(url)
                }
                .alert(
                    "Project Already Exists",
                    isPresented: Binding(
                        get: { appState.showBundleImportAlert },
                        set: { appState.showBundleImportAlert = $0 }
                    )
                ) {
                    Button("Replace") {
                        if let existing = appState.pendingImport?.existingProject {
                            appState.finalizeBundleImport(mode: .replace(existingID: existing.id))
                        }
                    }
                    Button("Keep Both") {
                        appState.finalizeBundleImport(mode: .keepBoth)
                    }
                    Button("Cancel", role: .cancel) {
                        if let temp = appState.pendingImport?.tempDirectory {
                            try? FileManager.default.removeItem(at: temp)
                        }
                        appState.pendingImport = nil
                    }
                } message: {
                    Text("A project named \"\(appState.pendingImport?.project.name ?? "")\" already exists.")
                }
                .alert(
                    "Import Failed",
                    isPresented: Binding(
                        get: { appState.showBundleImportError },
                        set: { appState.showBundleImportError = $0 }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(appState.bundleImportError ?? "")
                }
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .defaultSize(width: 950, height: 700)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        #endif
    }
}
