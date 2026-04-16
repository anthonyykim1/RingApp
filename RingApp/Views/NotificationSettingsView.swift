import SwiftUI

struct NotificationSettingsView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var settings: SettingsStore
    @State private var buzzes: Double = 3
    @State private var buzzDuration: Double = 800
    @State private var pauseDuration: Double = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "shortcuts")
                            .foregroundStyle(.blue)
                        Text("Set up in Shortcuts app")
                            .font(.subheadline)
                    }
                } header: {
                    Text("iMessage / SMS Automation")
                } footer: {
                    Text("Open the Shortcuts app → Automation → New → Message → select \"Run Immediately\" → search for \"Vibrate Ring\". This will vibrate the ring when you receive a text.")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Buzzes: \(Int(buzzes))")
                            .font(.subheadline)
                        Slider(value: $buzzes, in: 1...10, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("Buzz duration: \(Int(buzzDuration))ms")
                            .font(.subheadline)
                        Slider(value: $buzzDuration, in: 100...3000, step: 100)
                    }
                    VStack(alignment: .leading) {
                        Text("Pause between: \(Int(pauseDuration))ms")
                            .font(.subheadline)
                        Slider(value: $pauseDuration, in: 0...2000, step: 50)
                    }
                } header: {
                    Text("Vibration Pattern")
                } footer: {
                    Text("Pattern used by the Vibrate Ring shortcut and custom pattern test.")
                }

                Section {
                    Text("Phone calls vibrate automatically via ANCS — no setup needed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Phone Calls")
                }

                Section {
                    Toggle("App Events", isOn: $settings.appVibration)
                    Toggle("Health Events", isOn: $settings.healthVibration)
                    Toggle("Alarm Events", isOn: $settings.alarmVibration)
                    Toggle("Phone Calls", isOn: $settings.callVibration)
                    Toggle("Notifications", isOn: $settings.notificationVibration)
                    Toggle("Care Events", isOn: $settings.careVibration)

                    Button {
                        ble.setStatus(pairs: settings.allPairs)
                    } label: {
                        Label("Apply to Ring", systemImage: "arrow.up.circle.fill")
                    }
                    .disabled(ble.connectionState != .connected)
                } header: {
                    Text("Ring Firmware Types")
                } footer: {
                    Text("Configures ring-side ANCS vibration types. Only Phone Calls works automatically via ANCS.")
                }
            }
            .navigationTitle("Notifications")
            .onChange(of: buzzes) { _, val in ble.vibrationBuzzes = Int(val) }
            .onChange(of: buzzDuration) { _, val in ble.vibrationBuzzMs = Int(val) }
            .onChange(of: pauseDuration) { _, val in ble.vibrationPauseMs = Int(val) }
        }
    }
}
