import SwiftUI

struct GridView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 6) {
            ForEach((0..<8).reversed(), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { col in
                        PadView(position: GridPosition(row: row, column: col))
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text(appState.isEditMode ? "drag to rearrange" : "⌥ drag to rearrange")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.trailing, 18)
                .padding(.bottom, 4)
        }
        .overlay {
            if case .xyPad(_, let cursor) = appState.mode {
                VStack(spacing: 0) {
                    HStack {
                        Text("XY PAD")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .tracking(2)

                        Spacer()

                        if let c = cursor {
                            let noteName = AppState.pentatonicNoteNames[c.column]
                            let volume = Int((0.15 + (Float(c.row) / 7.0) * 0.85) * 100)

                            Text("\(noteName)  Vol: \(volume)%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Spacer()

                    HStack {
                        Label("← Notes →", systemImage: "arrow.left.arrow.right")
                        Spacer()
                        Label("↕ Volume", systemImage: "arrow.up.arrow.down")
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
                .background(.ultraThinMaterial.opacity(0.3))
                .allowsHitTesting(false)
            }
        }
        .padding(14)
        .background(
            ZStack {
                // Deep dark gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.06, blue: 0.12),
                        Color(red: 0.03, green: 0.03, blue: 0.08),
                        Color(red: 0.02, green: 0.02, blue: 0.05),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Subtle radial highlight in center (stage light feel)
                RadialGradient(
                    colors: [
                        Color.blue.opacity(0.04),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 50,
                    endRadius: 400
                )

                // Dot grid pattern overlay
                DotGridPattern()
                    .opacity(0.15)
            }
        )
    }
}

/// Subtle dot grid pattern for arena/stage floor feel
struct DotGridPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 20
            let dotSize: CGFloat = 1.0

            for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                    let rect = CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(0.3))
                    )
                }
            }
        }
    }
}
