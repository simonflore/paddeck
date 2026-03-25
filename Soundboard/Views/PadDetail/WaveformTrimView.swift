import SwiftUI
import DSWaveformImage
import DSWaveformImageViews

struct WaveformTrimView: View {
    let audioURL: URL
    @Binding var trimStart: Double
    @Binding var trimEnd: Double?
    let duration: Double

    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false

    private let handleWidth: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .leading) {
                // Dark background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.08))

                // Waveform
                WaveformView(audioURL: audioURL, configuration: .init(
                    style: .striped(.init(color: .init(white: 0.5, alpha: 1.0), width: 2, spacing: 1)),
                    damping: .init(percentage: 0.125, sides: .both),
                    verticalScalingFactor: 0.95
                ))

                // Active region highlight
                Rectangle()
                    .fill(Color.cyan.opacity(0.08))
                    .frame(
                        width: xPosition(for: effectiveEnd, in: width) - xPosition(for: trimStart, in: width)
                    )
                    .offset(x: xPosition(for: trimStart, in: width))

                // Dimmed regions (outside trim)
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: xPosition(for: trimStart, in: width))

                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: width - xPosition(for: effectiveEnd, in: width))
                    .offset(x: xPosition(for: effectiveEnd, in: width))

                // Start handle
                trimHandle(color: .cyan)
                    .offset(x: xPosition(for: trimStart, in: width) - handleWidth / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingStart = true
                                let newTime = timePosition(for: value.location.x, in: width)
                                trimStart = max(0, min(newTime, effectiveEnd - 0.05))
                            }
                            .onEnded { _ in isDraggingStart = false }
                    )

                // End handle
                trimHandle(color: .orange)
                    .offset(x: xPosition(for: effectiveEnd, in: width) - handleWidth / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingEnd = true
                                let newTime = timePosition(for: value.location.x, in: width)
                                trimEnd = min(duration, max(newTime, trimStart + 0.05))
                            }
                            .onEnded { _ in isDraggingEnd = false }
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var effectiveEnd: Double {
        trimEnd ?? duration
    }

    private func xPosition(for time: Double, in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    private func timePosition(for x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(x / width) * duration
    }

    private func trimHandle(color: Color) -> some View {
        ZStack {
            // Handle glow
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.3))
                .frame(width: handleWidth + 4)
                .blur(radius: 3)

            // Handle body
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: handleWidth)
                .overlay(
                    // Grip lines
                    VStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(.white.opacity(0.5))
                                .frame(width: 4, height: 1)
                        }
                    }
                )
        }
        .contentShape(Rectangle().size(width: handleWidth * 3, height: 200))
    }
}
