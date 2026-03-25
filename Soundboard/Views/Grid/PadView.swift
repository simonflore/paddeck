import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PadView: View {
    @Environment(AppState.self) private var appState
    let position: GridPosition

    @State private var isHovering = false
    @State private var isPressed = false
    @State private var isDropTargeted = false

    private var pad: PadConfiguration {
        appState.project.pad(at: position)
    }

    private var isPlaying: Bool {
        appState.audioEngine.activePads.contains(position)
    }

    private var isSelected: Bool {
        appState.selectedPad == position
    }

    private var padColor: Color {
        pad.isEmpty ? Color(white: 0.18) : pad.color.swiftUIColor
    }

    var body: some View {
        ZStack {
            // Glow layer (behind the pad)
            if !pad.isEmpty {
                RoundedRectangle(cornerRadius: 10)
                    .fill(padColor.opacity(isPlaying ? 0.6 : (isHovering ? 0.3 : 0.15)))
                    .blur(radius: isPlaying ? 12 : (isHovering ? 8 : 5))
                    .scaleEffect(isPlaying ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPlaying)
            }

            // Main pad body
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: pad.isEmpty
                            ? [Color(white: 0.14), Color(white: 0.10)]
                            : [padColor.opacity(0.85), padColor.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Inner highlight (top-left light reflection)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(pad.isEmpty ? 0.03 : 0.15), .clear],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                )
                .overlay(
                    // Border
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected
                                ? Color.white.opacity(0.9)
                                : (isHovering ? Color.white.opacity(0.3) : Color.white.opacity(0.08)),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            // Content
            VStack(spacing: 0) {
                if let sample = pad.sample {
                    Spacer(minLength: 0)

                    if let emoji = pad.emoji {
                        Text(emoji)
                            .font(.system(size: 28))
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    }

                    Text(sample.name)
                        .font(.system(size: pad.emoji != nil ? 10 : 13, weight: .semibold, design: .rounded))
                        .lineLimit(pad.emoji != nil ? 1 : 2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(pad.emoji != nil ? 0.7 : 1.0))
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)

                    Spacer(minLength: 0)

                    Text(formatDuration(sample.effectiveDuration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                } else {
                    // Empty pad — subtle plus icon
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.white.opacity(isHovering ? 0.25 : 0.08))
                }
            }
            .padding(4)

            // Playback indicator
            if isPlaying {
                PlaybackIndicator()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(isPressed ? 0.92 : (isHovering ? 1.03 : 1.0))
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .overlay {
            PadMouseOverlay(
                position: position,
                isEditMode: appState.isEditMode,
                onPress: {
                    isPressed = true
                    if appState.isEditMode {
                        // Edit mode: select only, no playback
                        appState.selectedPad = position
                        appState.updateXYButtonLED()
                    } else {
                        let velocity = PressureTracker.shared.velocity
                        appState.handlePadPress(position: position, velocity: velocity)
                    }
                },
                onRelease: {
                    isPressed = false
                    if !appState.isEditMode {
                        appState.handlePadRelease(position: position)
                    }
                },
                onPressStateChanged: { isPressed = $0 }
            )
        }
        .onDrop(of: [.json, .fileURL], isTargeted: $isDropTargeted) { providers in
            // Pad swap (GridPosition encoded as JSON via Transferable)
            if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.json.identifier) }) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, _ in
                    guard let data, let source = try? JSONDecoder().decode(GridPosition.self, from: data) else { return }
                    DispatchQueue.main.async {
                        appState.swapPads(source, position)
                    }
                }
                return true
            }
            // File import
            let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
            guard !fileProviders.isEmpty else { return false }

            if fileProviders.count == 1 {
                // Single file: import to this specific pad
                _ = fileProviders[0].loadObject(ofClass: URL.self) { url, _ in
                    guard let url, AudioFormats.isSupported(url) else { return }
                    DispatchQueue.main.async {
                        _ = importFile(url: url)
                    }
                }
            } else {
                // Multiple files: bulk import to free pads
                let group = DispatchGroup()
                var urls: [URL] = []
                let lock = NSLock()
                for provider in fileProviders {
                    group.enter()
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url {
                            lock.lock()
                            urls.append(url)
                            lock.unlock()
                        }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    appState.importFilesToFreePads(urls: urls)
                }
            }
            return true
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        } else if seconds < 10 {
            return String(format: "%.1fs", seconds)
        } else {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return mins > 0 ? String(format: "%d:%02d", mins, secs) : String(format: "%ds", secs)
        }
    }

    private func importFile(url: URL) -> Bool {
        guard let sample = try? appState.sampleStore.importAudioFile(from: url) else {
            return false
        }
        var padConfig = pad
        padConfig.sample = sample
        if padConfig.color == .off {
            padConfig.color = .defaultLoaded
        }
        appState.updatePad(padConfig, at: position)
        return true
    }
}

// MARK: - AppKit mouse handler (avoids SwiftUI gesture conflicts with drag)

private struct PadMouseOverlay: NSViewRepresentable {
    let position: GridPosition
    let isEditMode: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    let onPressStateChanged: (Bool) -> Void

    func makeNSView(context: Context) -> PadMouseNSView {
        let view = PadMouseNSView()
        view.position = position
        view.isEditMode = isEditMode
        view.onPress = onPress
        view.onRelease = onRelease
        view.onPressStateChanged = onPressStateChanged
        return view
    }

    func updateNSView(_ nsView: PadMouseNSView, context: Context) {
        nsView.position = position
        nsView.isEditMode = isEditMode
        nsView.onPress = onPress
        nsView.onRelease = onRelease
        nsView.onPressStateChanged = onPressStateChanged
    }
}

final class PadMouseNSView: NSView, NSDraggingSource {
    var position: GridPosition!
    var isEditMode = false
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onPressStateChanged: ((Bool) -> Void)?
    private var isDragSession = false
    private var mouseDownLocation: NSPoint = .zero
    private var didPress = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    // MARK: Mouse events

    /// In edit mode, dragging works without Option key.
    /// In play mode, Option key is still required.
    private var canDrag: Bool {
        isEditMode
    }

    override func mouseDown(with event: NSEvent) {
        isDragSession = false
        didPress = false
        mouseDownLocation = event.locationInWindow
        onPressStateChanged?(true)

        // In play mode, Option starts a drag instead of pressing
        if !isEditMode && event.modifierFlags.contains(.option) {
            return
        }

        didPress = true
        onPress?()
    }

    override func mouseDragged(with event: NSEvent) {
        let allowDrag = isEditMode || event.modifierFlags.contains(.option)
        guard allowDrag, !isDragSession else { return }

        let loc = event.locationInWindow
        let dx = loc.x - mouseDownLocation.x
        let dy = loc.y - mouseDownLocation.y
        guard sqrt(dx * dx + dy * dy) > 4 else { return }

        isDragSession = true

        let data = try! JSONEncoder().encode(position!)
        let pbItem = NSPasteboardItem()
        pbItem.setData(data, forType: NSPasteboard.PasteboardType(UTType.json.identifier))

        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        dragItem.setDraggingFrame(bounds, contents: NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.white.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            return true
        })

        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        onPressStateChanged?(false)
        guard !isDragSession else {
            isDragSession = false
            return
        }
        if didPress {
            onRelease?()
        }
        didPress = false
    }
}
