import SwiftUI
import UniformTypeIdentifiers

// MARK: - EffectOption Protocol

protocol EffectOption: Identifiable {
    var displayName: String { get }
    var iconName: String { get }
}

extension PlayMode: EffectOption {}
extension VocalEffect: EffectOption {}
extension VocalActivationMode: EffectOption {}

struct PadDetailView: View {
    @Environment(AppState.self) private var appState

    private var position: GridPosition {
        guard let pos = appState.selectedPad else {
            assertionFailure("PadDetailView shown with nil selectedPad")
            return GridPosition(row: 0, column: 0)
        }
        return pos
    }

    private var pad: PadConfiguration {
        appState.project.pad(at: position)
    }

    private var accentColor: Color {
        if pad.isVocalPad { return .purple }
        return pad.isEmpty ? .blue : pad.color.swiftUIColor
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PAD \(position.row + 1).\(position.column + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .tracking(1.5)

                        if pad.isVocalPad {
                            HStack(spacing: 4) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 14))
                                Text("Live Vocal")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.purple)
                        } else if let sample = pad.sample {
                            Text(sample.name)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        } else {
                            Text("Empty Pad")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Pad color preview dot
                    if !pad.isEmpty {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .fill(accentColor.opacity(0.3))
                                    .frame(width: 26, height: 26)
                            )
                    }

                    Button {
                        appState.selectedPad = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if pad.isVocalPad, let vocalConfig = pad.vocalConfig {
                    // Effect selector
                    DetailSection(title: "EFFECT", icon: "waveform.path.ecg") {
                        HStack(spacing: 6) {
                            ForEach(VocalEffect.allCases) { effect in
                                PlayModeButton(
                                    mode: effect,
                                    isSelected: vocalConfig.effect == effect,
                                    accentColor: accentColor
                                ) {
                                    var p = pad
                                    p.vocalConfig?.effect = effect
                                    appState.updatePad(p, at: position)
                                }
                            }
                        }
                    }

                    // Activation mode
                    DetailSection(title: "ACTIVATION", icon: "hand.tap") {
                        HStack(spacing: 6) {
                            ForEach(VocalActivationMode.allCases) { mode in
                                PlayModeButton(
                                    mode: mode,
                                    isSelected: vocalConfig.activationMode == mode,
                                    accentColor: accentColor
                                ) {
                                    var p = pad
                                    p.vocalConfig?.activationMode = mode
                                    appState.updatePad(p, at: position)
                                }
                            }
                        }
                    }

                    // Dry/Wet slider
                    DetailSection(title: "DRY / WET", icon: "slider.horizontal.3") {
                        HStack(spacing: 8) {
                            Text("Dry")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            Slider(value: Binding(
                                get: { vocalConfig.dryWetMix },
                                set: { newVal in
                                    var p = pad
                                    p.vocalConfig?.dryWetMix = newVal
                                    appState.updatePad(p, at: position)
                                }
                            ), in: 0...1)
                            .tint(accentColor)

                            Text("Wet")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text("\(Int(vocalConfig.dryWetMix * 100))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }

                    // Color
                    DetailSection(title: "COLOR", icon: "paintpalette") {
                        ColorPickerView(color: Binding(
                            get: { pad.color },
                            set: { newColor in
                                var p = pad
                                p.color = newColor
                                appState.updatePad(p, at: position)
                            }
                        ))
                    }

                    // Remove vocal action
                    HStack {
                        Spacer()
                        Button {
                            var p = pad
                            p.vocalConfig = nil
                            p.color = .off
                            appState.updatePad(p, at: position)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("Remove Vocal")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)

                } else if let sample = pad.sample {
                    // Emoji
                    DetailSection(title: "EMOJI", icon: "face.smiling") {
                        HStack(spacing: 10) {
                            EmojiTextField(emoji: Binding(
                                get: { pad.emoji ?? "" },
                                set: { newEmoji in
                                    var p = pad
                                    p.emoji = newEmoji.isEmpty ? nil : String(newEmoji.prefix(1))
                                    appState.updatePad(p, at: position)
                                }
                            ))
                            .frame(width: 44, height: 44)

                            if pad.emoji != nil {
                                Button {
                                    var p = pad
                                    p.emoji = nil
                                    appState.updatePad(p, at: position)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer()
                        }
                    }

                    // Sample Name Editor
                    DetailSection(title: "NAME", icon: "textformat") {
                        TextField("Sample Name", text: Binding(
                            get: { sample.name },
                            set: { newName in
                                var p = pad
                                p.sample?.name = newName
                                appState.updatePad(p, at: position)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .rounded))
                    }

                    // Waveform + Trim
                    if let url = appState.sampleStore.audioFileURL(for: sample) {
                        DetailSection(title: "WAVEFORM", icon: "waveform") {
                            WaveformTrimView(
                                audioURL: url,
                                trimStart: Binding(
                                    get: { sample.trimStart },
                                    set: { newStart in
                                        var p = pad
                                        p.sample?.trimStart = newStart
                                        appState.updatePad(p, at: position)
                                    }
                                ),
                                trimEnd: Binding(
                                    get: { sample.trimEnd },
                                    set: { newEnd in
                                        var p = pad
                                        p.sample?.trimEnd = newEnd
                                        appState.updatePad(p, at: position)
                                    }
                                ),
                                duration: sample.fileDuration
                            )
                            .frame(height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            // Duration info
                            HStack {
                                Label(
                                    String(format: "%.1fs total", sample.fileDuration),
                                    systemImage: "clock"
                                )
                                Spacer()
                                Label(
                                    String(format: "%.1fs trimmed", sample.effectiveDuration),
                                    systemImage: "scissors"
                                )
                            }
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        }
                    }

                    // Play Mode
                    DetailSection(title: "PLAY MODE", icon: "play.circle") {
                        HStack(spacing: 6) {
                            ForEach(PlayMode.allCases) { mode in
                                PlayModeButton(
                                    mode: mode,
                                    isSelected: pad.playMode == mode,
                                    accentColor: accentColor
                                ) {
                                    var p = pad
                                    p.playMode = mode
                                    appState.updatePad(p, at: position)
                                }
                            }
                        }
                    }

                    // Volume
                    DetailSection(title: "VOLUME", icon: "speaker.wave.2") {
                        HStack(spacing: 8) {
                            Image(systemName: volumeIcon)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            Slider(value: Binding(
                                get: { pad.volume },
                                set: { newVol in
                                    var p = pad
                                    p.volume = newVol
                                    appState.updatePad(p, at: position)
                                }
                            ), in: 0...1)
                            .tint(accentColor)

                            Text("\(Int(pad.volume * 100))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }

                    // Color
                    DetailSection(title: "COLOR", icon: "paintpalette") {
                        ColorPickerView(color: Binding(
                            get: { pad.color },
                            set: { newColor in
                                var p = pad
                                p.color = newColor
                                appState.updatePad(p, at: position)
                            }
                        ))
                    }

                    // Actions
                    HStack(spacing: 10) {
                        Button {
                            appState.audioEngine.play(pad: pad)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10))
                                Text("Preview")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(accentColor.opacity(0.2))
                            .foregroundStyle(accentColor)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(accentColor.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            appState.sampleStore.deleteAudioFile(for: sample)
                            var p = pad
                            p.sample = nil
                            p.color = .off
                            appState.updatePad(p, at: position)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("Remove")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)

                } else {
                    // Empty pad — drop target
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.08))
                                .frame(width: 70, height: 70)

                            Circle()
                                .strokeBorder(Color.blue.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                .frame(width: 70, height: 70)

                            Image(systemName: "waveform.badge.plus")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.blue.opacity(0.5))
                        }

                        Text("Drop an audio file here\nor use Record to create a sample")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)

                    // Live Vocal button
                    DetailSection(title: "LIVE VOCAL", icon: "mic.fill") {
                        Button {
                            assignVocalPad()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.purple)

                                Text("Assign as Live Vocal")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Spacer()

                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.purple.opacity(0.6))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.purple.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Factory samples
                    DetailSection(title: "FACTORY SAMPLES", icon: "waveform.circle") {
                        VStack(spacing: 6) {
                            ForEach(Array(FactorySampleGenerator.presets.enumerated()), id: \.offset) { _, preset in
                                FactorySampleButton(preset: preset) {
                                    loadFactorySample(preset)
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color(red: 0.06, green: 0.06, blue: 0.09),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, AudioFormats.isSupported(url) else { return false }
            return importFile(url: url)
        }
    }

    // MARK: - File Import

    private func importFile(url: URL) -> Bool {
        guard let sample = try? appState.sampleStore.importAudioFile(from: url) else {
            return false
        }
        var padConfig = pad
        padConfig.sample = sample
        padConfig.vocalConfig = nil
        if padConfig.color == .off {
            padConfig.color = .defaultLoaded
        }
        appState.updatePad(padConfig, at: position)
        return true
    }

    private func loadFactorySample(_ preset: FactorySampleGenerator.FactoryPreset) {
        guard let sample = FactorySampleGenerator.generate(
            preset: preset,
            in: appState.sampleStore.audioDirectory
        ) else { return }
        var padConfig = pad
        padConfig.sample = sample
        padConfig.color = preset.color
        padConfig.playMode = .oneShotStopOnRelease
        appState.updatePad(padConfig, at: position)
    }

    private func assignVocalPad() {
        // If another pad is already vocal, clear it
        if let existingPos = appState.vocalPadPosition, existingPos != position {
            var oldPad = appState.project.pad(at: existingPos)
            oldPad.vocalConfig = nil
            oldPad.color = .off
            appState.updatePad(oldPad, at: existingPos)
        }

        var padConfig = pad
        padConfig.vocalConfig = VocalPadConfig()
        padConfig.sample = nil
        padConfig.color = LaunchpadColor(r: 127, g: 0, b: 80) // magenta
        appState.updatePad(padConfig, at: position)
    }

    private var volumeIcon: String {
        if pad.volume == 0 { return "speaker.slash.fill" }
        if pad.volume < 0.33 { return "speaker.fill" }
        if pad.volume < 0.66 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }
}

// MARK: - Detail Section

struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }

            content
        }
    }
}

// MARK: - Play Mode Button

struct PlayModeButton<Option: EffectOption>: View {
    let mode: Option
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 14, weight: .medium))

                Text(mode.displayName)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? accentColor.opacity(0.2) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? accentColor.opacity(0.5) : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isSelected ? accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Factory Sample Button

struct FactorySampleButton: View {
    let preset: FactorySampleGenerator.FactoryPreset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(preset.color.swiftUIColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .fill(preset.color.swiftUIColor.opacity(0.3))
                            .frame(width: 18, height: 18)
                    )

                Text(preset.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text(String(format: "%.1fs", preset.duration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
