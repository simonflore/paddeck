import SwiftUI

struct GridView: View {
    @Environment(AppState.self) private var appState

    private var dragHintText: Text {
        #if os(macOS)
        Text(appState.isEditMode ? "drag to rearrange" : "⌥ drag to rearrange")
        #else
        Text(appState.isEditMode ? "hold & drag to rearrange" : "")
        #endif
    }

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
            dragHintText
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.trailing, 18)
                .padding(.bottom, 4)
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
