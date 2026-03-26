import SwiftUI

struct PlaybackIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.6)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3)
                    .frame(height: isAnimating ? barHeight(for: index) : 3)
                    .animation(
                        .easeInOut(duration: barDuration(for: index))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 14, height: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(5)
        .onAppear { isAnimating = true }
    }

    private func barHeight(for index: Int) -> CGFloat {
        switch index {
        case 0: return 10
        case 1: return 12
        case 2: return 7
        default: return 8
        }
    }

    private func barDuration(for index: Int) -> Double {
        switch index {
        case 0: return 0.4
        case 1: return 0.3
        case 2: return 0.5
        default: return 0.4
        }
    }
}
