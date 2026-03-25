import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    private var isXYMode: Bool {
        if case .xyPad = appState.mode { return true }
        return false
    }

    private var canEnterXY: Bool {
        isXYMode || appState.canEnterXYMode
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                GridView()

                // Action bar
                HStack(spacing: 0) {
                    // MIDI status — leading
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.midiManager.isConnected ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle()
                                    .fill(appState.midiManager.isConnected ? Color.green.opacity(0.3) : Color.clear)
                                    .frame(width: 13, height: 13)
                            )

                        Text(appState.midiManager.isConnected ? appState.midiManager.deviceName : "No Launchpad")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(appState.midiManager.isConnected ? .primary : .secondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        // Play / Edit toggle
                        Button {
                            appState.isEditMode.toggle()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: appState.isEditMode ? "pencil" : "play.fill")
                                    .font(.system(size: 12))
                                Text(appState.isEditMode ? "Edit" : "Play")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                appState.isEditMode
                                    ? Color.orange.opacity(0.35)
                                    : Color.white.opacity(0.05)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(
                                        appState.isEditMode ? Color.orange.opacity(0.5) : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)

                        // XY Performance Pad toggle
                        Button {
                            appState.toggleXYMode()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "slider.horizontal.2.square")
                                    .font(.system(size: 12))
                                    .symbolRenderingMode(.hierarchical)
                                Text("XY Pad")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isXYMode
                                    ? Color.blue.opacity(0.35)
                                    : Color.white.opacity(0.05)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(
                                        isXYMode ? Color.blue.opacity(0.5) : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canEnterXY)
                        .opacity(canEnterXY ? 1.0 : 0.35)

                        // Stop All button
                        Button {
                            if case .xyPad = appState.mode { appState.exitXYMode() }
                            appState.audioEngine.stopAll()
                            appState.midiManager.syncLEDs(with: appState.project, playingPads: appState.audioEngine.activePads)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 10))
                                Text("Stop All")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)

                        // Record button
                        Button {
                            appState.isRecordingPresented = true
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle()
                                            .fill(.red.opacity(0.4))
                                            .frame(width: 14, height: 14)
                                    )
                                Text("Record")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.red.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Color(red: 0.04, green: 0.04, blue: 0.08)
                        .overlay(
                            Rectangle()
                                .fill(Color.white.opacity(0.03))
                                .frame(height: 1),
                            alignment: .top
                        )
                )
            }
            .frame(minWidth: 500)

            if appState.selectedPad != nil {
                PadDetailView()
                    .frame(minWidth: 300, maxWidth: 400)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.isRecordingPresented },
            set: { appState.isRecordingPresented = $0 }
        )) {
            RecordView()
                .environment(appState)
        }
        .alert(
            "Import Complete",
            isPresented: Binding(
                get: { appState.showImportAlert },
                set: { appState.showImportAlert = $0 }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.importAlertMessage)
        }
    }
}
