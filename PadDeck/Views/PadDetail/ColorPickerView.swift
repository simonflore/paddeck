import SwiftUI

struct ColorPickerView: View {
    @Binding var color: LaunchpadColor

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(Array(LaunchpadColor.presets.enumerated()), id: \.offset) { _, preset in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(preset.swiftUIColor)
                        .frame(height: 28)

                    if color == preset {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white, lineWidth: 2)

                        RoundedRectangle(cornerRadius: 8)
                            .fill(preset.swiftUIColor.opacity(0.3))
                            .blur(radius: 4)
                    }
                }
                .frame(height: 28)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        color = preset
                    }
                }
            }
        }
    }
}
