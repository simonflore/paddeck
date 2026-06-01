import SwiftUI

struct TransportBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            // Synced / Internal indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(appState.transportClock.isLocked ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(appState.transportClock.isLocked ? "Synced" : "Internal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            // Tempo readout
            Text(String(format: "%.1f BPM", displayedBPM))
                .font(.system(size: 13, weight: .bold, design: .monospaced))

            // Position
            let p = appState.transportClock.position
            Text(String(format: "%d.%d.%02d", p.bar, p.beat, p.tick))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer()

            // Global quantize selector
            Picker("Quantize", selection: Binding(
                get: { appState.transportSettings.globalQuantize },
                set: { appState.transportSettings.globalQuantize = $0 }
            )) {
                ForEach(Quantization.allCases) { q in
                    Text(q.displayName).tag(q)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 110)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private var displayedBPM: Double {
        appState.transportClock.isLocked
            ? appState.transportClock.displayBPM
            : appState.transportSettings.manualBPM
    }
}
