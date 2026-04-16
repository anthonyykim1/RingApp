import SwiftUI

struct TestView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var selectedType: UInt8 = 1
    @State private var intensity: Double = 255
    @State private var buzzes: Double = 3
    @State private var buzzDuration: Double = 800
    @State private var pauseDuration: Double = 0

    private let vibrateTypes: [(UInt8, String)] = [
        (1, "App Event"),
        (2, "Health Event"),
        (3, "Alarm Event"),
        (4, "Call Event"),
        (5, "Notification Event"),
        (6, "Care Event"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Start / Stop") {
                    Button {
                        ble.startVibration()
                    } label: {
                        Label("Start Vibration", systemImage: "play.fill")
                    }
                    .disabled(ble.connectionState != .connected)

                    Button {
                        ble.stopVibration()
                    } label: {
                        Label("Stop Vibration", systemImage: "stop.fill")
                    }
                    .disabled(ble.connectionState != .connected)
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
                    Button {
                        ble.sendRepeatedVibration(
                            buzzes: Int(buzzes),
                            buzzMs: Int(buzzDuration),
                            pauseMs: Int(pauseDuration)
                        )
                    } label: {
                        Label("Send \(Int(buzzes))x Buzzes", systemImage: "repeat")
                    }
                    .disabled(ble.connectionState != .connected)
                } header: {
                    Text("Custom Pattern")
                } footer: {
                    Text("Sends start → wait → stop for each buzz. Adjust duration and pause to find your preferred pattern.")
                }

                Section {
                    Button {
                        ble.getSitRemind()
                    } label: {
                        Label("Read Setting", systemImage: "arrow.down.circle")
                    }
                    .disabled(ble.connectionState != .connected)

                    Button {
                        ble.disableSitRemind()
                    } label: {
                        Label("Disable Sedentary Reminder", systemImage: "bell.slash")
                    }
                    .disabled(ble.connectionState != .connected)

                    Button {
                        ble.disableAllReminders()
                    } label: {
                        Label("Disable All (keep calls)", systemImage: "bell.slash.fill")
                    }
                    .disabled(ble.connectionState != .connected)

                    Button {
                        ble.disableSedentaryConfig()
                    } label: {
                        Label("Disable via 0x15 Config", systemImage: "xmark.circle")
                    }
                    .disabled(ble.connectionState != .connected)

                    Button {
                        ble.getSwitchConfig()
                        ble.getDeviceConfig()
                        ble.getHeartRateInterval()
                    } label: {
                        Label("Query Ring Config", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(ble.connectionState != .connected)

                    Button {
                        ble.setHeartRateInterval(0)
                    } label: {
                        Label("Disable HR Monitoring", systemImage: "heart.slash")
                    }
                    .disabled(ble.connectionState != .connected)
                } header: {
                    Text("Sedentary Reminder")
                } footer: {
                    Text("Ring buzzes every 30 min if sedentary reminder is enabled in firmware. Read first to check, then disable.")
                }

                Section("Raw Commands") {
                    Button {
                        ble.sendVibratePhone(type: selectedType)
                    } label: {
                        Label("vibratePhone (type=\(selectedType))",
                              systemImage: "iphone.radiowaves.left.and.right")
                    }
                    .disabled(ble.connectionState != .connected)

                    Button {
                        ble.sendExperience(type: selectedType, intensity: UInt8(intensity))
                    } label: {
                        Label("sendExperience (type=\(selectedType), int=\(Int(intensity)))",
                              systemImage: "waveform.path")
                    }
                    .disabled(ble.connectionState != .connected)

                    VStack(alignment: .leading) {
                        Text("Intensity: \(Int(intensity))")
                            .font(.subheadline)
                        Slider(value: $intensity, in: 0...255, step: 1)
                    }

                    Picker("Event Type", selection: $selectedType) {
                        ForEach(vibrateTypes, id: \.0) { value, name in
                            Text(name).tag(value)
                        }
                    }
                }

                Section("Log (\(ble.log.count))") {
                    HStack {
                        Button("Copy Log") {
                            let contents = (try? String(contentsOf: BLEManager.persistentLogURL, encoding: .utf8)) ?? "empty"
                            UIPasteboard.general.string = contents
                        }
                        Spacer()
                        Button("Clear") { ble.clearPersistentLog() }
                            .foregroundStyle(.red)
                    }
                    if ble.log.isEmpty {
                        Text("No activity yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(ble.log.reversed().enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            .navigationTitle("Test")
        }
    }
}
