import SwiftUI

struct RecordView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isRecording = false
    @State private var recordingURL: URL?
    @State private var sampleName = ""
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var pulseScale: CGFloat = 1.0
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text("Record Sample")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            // Recording visualization
            ZStack {
                // Outer pulse rings
                if isRecording {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .strokeBorder(Color.red.opacity(0.15), lineWidth: 1.5)
                            .frame(width: 90 + CGFloat(i) * 30, height: 90 + CGFloat(i) * 30)
                            .scaleEffect(pulseScale)
                            .opacity(2.0 - Double(pulseScale))
                            .animation(
                                .easeOut(duration: 1.5)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(i) * 0.4),
                                value: pulseScale
                            )
                    }
                }

                // Glow behind button
                Circle()
                    .fill(isRecording ? Color.red.opacity(0.2) : Color.gray.opacity(0.05))
                    .frame(width: 80, height: 80)
                    .blur(radius: 15)

                // Main record button
                Circle()
                    .fill(
                        RadialGradient(
                            colors: isRecording
                                ? [.red, .red.opacity(0.7)]
                                : [Color(white: 0.25), Color(white: 0.18)],
                            center: .center,
                            startRadius: 5,
                            endRadius: 35
                        )
                    )
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(isRecording ? 0.3 : 0.1), lineWidth: 1)
                    )
                    .shadow(color: isRecording ? .red.opacity(0.5) : .clear, radius: 15)

                // Inner icon
                if isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 18, height: 18)
                } else if recordingURL == nil {
                    Circle()
                        .fill(.red)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 160)

            // Timer display
            Text(formatDuration(recordingDuration))
                .font(.system(size: 36, weight: .light, design: .monospaced))
                .foregroundStyle(isRecording ? .red : .secondary)
                .contentTransition(.numericText())

            // Name field (post-recording)
            if recordingURL != nil && !isRecording {
                TextField("Sample Name", text: $sampleName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .rounded))
                    .frame(maxWidth: 280)
            }

            // Controls
            HStack(spacing: 14) {
                if isRecording {
                    RecordActionButton(title: "Stop", icon: "stop.fill", color: .red) {
                        stopRecording()
                    }
                } else if recordingURL != nil {
                    RecordActionButton(title: "Re-record", icon: "arrow.counterclockwise", color: .secondary) {
                        recordingURL = nil
                        recordingDuration = 0
                        startRecording()
                    }

                    RecordActionButton(title: "Save to Pad", icon: "square.and.arrow.down", color: .green) {
                        saveRecording()
                    }
                    .disabled(sampleName.isEmpty)
                    .opacity(sampleName.isEmpty ? 0.5 : 1)
                } else {
                    RecordActionButton(title: "Start Recording", icon: "mic.fill", color: .red) {
                        startRecording()
                    }
                }

                RecordActionButton(title: "Cancel", icon: "xmark", color: Color(white: 0.4)) {
                    cancelRecording()
                }
            }
        }
        .padding(36)
        .frame(minWidth: 420, minHeight: 340)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color(red: 0.05, green: 0.05, blue: 0.08),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .alert("Save Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Actions

    private func startRecording() {
        do {
            recordingURL = try appState.audioEngine.startRecording()
            isRecording = true
            recordingDuration = 0
            pulseScale = 1.8
            let start = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingDuration = Date().timeIntervalSince(start)
            }
        } catch {
            print("Failed to start recording: \(error)")
            recordingURL = nil
        }
    }

    private func stopRecording() {
        recordingURL = appState.audioEngine.stopRecording()
        isRecording = false
        pulseScale = 1.0
        timer?.invalidate()
        timer = nil

        if sampleName.isEmpty {
            sampleName = "Recording \(Date().formatted(date: .abbreviated, time: .shortened))"
        }
    }

    private func saveRecording() {
        guard let url = recordingURL,
              let position = appState.selectedPad ?? firstEmptyPad() else { return }

        do {
            let sample = try appState.sampleStore.sampleFromRecording(url: url, name: sampleName)
            var pad = appState.project.pad(at: position)
            pad.sample = sample
            if pad.color == .off {
                pad.color = .defaultLoaded
            }
            appState.updatePad(pad, at: position)
            appState.selectedPad = position
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelRecording() {
        if isRecording {
            appState.audioEngine.stopRecording()
        }
        timer?.invalidate()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        dismiss()
    }

    private func firstEmptyPad() -> GridPosition? {
        for row in 0..<8 {
            for col in 0..<8 {
                let pos = GridPosition(row: row, column: col)
                if appState.project.pad(at: pos).isEmpty {
                    return pos
                }
            }
        }
        return nil
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Action Button

struct RecordActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(color.opacity(0.15))
            .foregroundStyle(color == Color(white: 0.4) ? .secondary : color)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
