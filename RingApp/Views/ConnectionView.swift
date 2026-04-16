import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Ring icon
                Image(systemName: ringIcon)
                    .font(.system(size: 80))
                    .foregroundStyle(ringColor)
                    .symbolEffect(.pulse, isActive: isPulsing)

                // Connection status
                Text(ble.connectionState.rawValue)
                    .font(.title2.weight(.medium))

                Text("AIZO RING")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Battery level
                if let battery = ble.batteryLevel {
                    Text("Battery: \(battery)%")
                        .font(.subheadline)
                        .foregroundStyle(batteryColor(battery))
                }

                // Last vibration timestamp
                if let last = ble.lastVibrationSent {
                    Text("Last vibration: \(last.formatted(date: .omitted, time: .standard))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Connect / Disconnect
                Button {
                    if ble.connectionState == .disconnected {
                        ble.startScan()
                    } else {
                        ble.disconnect()
                    }
                } label: {
                    Text(ble.connectionState == .disconnected ? "Connect" : "Disconnect")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(ble.connectionState == .disconnected ? .blue : .red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationTitle("Ring")
        }
    }

    private var isPulsing: Bool {
        ble.connectionState == .scanning
        || ble.connectionState == .connecting
        || ble.connectionState == .discoveringServices
    }

    private var ringIcon: String {
        switch ble.connectionState {
        case .connected: "circle.circle.fill"
        case .scanning, .connecting, .discoveringServices: "circle.dashed"
        case .disconnected: "circle.circle"
        }
    }

    private var ringColor: Color {
        switch ble.connectionState {
        case .connected: .green
        case .scanning, .connecting, .discoveringServices: .orange
        case .disconnected: .gray
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case 76...100: "battery.100percent"
        case 51...75: "battery.75percent"
        case 26...50: "battery.50percent"
        case 1...25: "battery.25percent"
        default: "battery.0percent"
        }
    }

    private func batteryColor(_ level: Int) -> Color {
        switch level {
        case 51...100: .green
        case 21...50: .yellow
        default: .red
        }
    }
}
