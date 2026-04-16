import SwiftUI

struct AlarmView: View {
    @EnvironmentObject var alarmStore: AlarmStore
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                if alarmStore.alarms.isEmpty {
                    Text("No alarms set")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(alarmStore.alarms) { alarm in
                        AlarmRow(alarm: alarm)
                    }
                    .onDelete(perform: alarmStore.delete)
                }
            }
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AlarmEditView(alarmStore: alarmStore)
            }
        }
    }
}

struct AlarmRow: View {
    @EnvironmentObject var alarmStore: AlarmStore
    let alarm: Alarm

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.timeString)
                    .font(.system(size: 36, weight: .light, design: .rounded))
                    .foregroundStyle(alarm.enabled ? .primary : .tertiary)
                HStack(spacing: 8) {
                    if !alarm.label.isEmpty {
                        Text(alarm.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(alarm.repeatDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(alarm.buzzes) buzzes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { alarm.enabled },
                set: { _ in alarmStore.toggle(alarm) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct AlarmEditView: View {
    @ObservedObject var alarmStore: AlarmStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedTime = Date()
    @State private var label = ""
    @State private var buzzes: Double = 10
    @State private var repeatDays: Set<Int> = []

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                Section("Label") {
                    TextField("Alarm label", text: $label)
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Vibrations: \(Int(buzzes))")
                            .font(.subheadline)
                        Slider(value: $buzzes, in: 1...20, step: 1)
                    }
                } header: {
                    Text("Vibration Count")
                }

                Section("Repeat") {
                    ForEach(0..<7) { i in
                        let day = i + 1 // 1=Sun ... 7=Sat
                        Button {
                            if repeatDays.contains(day) {
                                repeatDays.remove(day)
                            } else {
                                repeatDays.insert(day)
                            }
                        } label: {
                            HStack {
                                Text(dayNames[i])
                                    .foregroundStyle(.primary)
                                Spacer()
                                if repeatDays.contains(day) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cal = Calendar.current
                        let alarm = Alarm(
                            hour: cal.component(.hour, from: selectedTime),
                            minute: cal.component(.minute, from: selectedTime),
                            enabled: true,
                            buzzes: Int(buzzes),
                            label: label,
                            repeatDays: repeatDays
                        )
                        alarmStore.add(alarm)
                        dismiss()
                    }
                }
            }
        }
    }
}
