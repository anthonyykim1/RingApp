import Foundation
import SwiftUI

struct Alarm: Identifiable, Codable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    var enabled: Bool = true
    var buzzes: Int = 10
    var label: String = ""
    var repeatDays: Set<Int> = [] // empty = one-time, 1=Sun, 2=Mon, ..., 7=Sat

    var timeString: String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h, minute, ampm)
    }

    var repeatDescription: String {
        if repeatDays.isEmpty { return "Once" }
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sorted = repeatDays.sorted()
        if sorted == [2, 3, 4, 5, 6] { return "Weekdays" }
        if sorted == [1, 7] { return "Weekends" }
        if sorted == Array(1...7) { return "Every day" }
        return sorted.map { names[$0] }.joined(separator: ", ")
    }
}

@MainActor
final class AlarmStore: ObservableObject {
    @Published var alarms: [Alarm] = [] {
        didSet { save() }
    }
    @Published var lastFiredAlarmID: UUID?

    private let key = "savedAlarms"

    init() {
        load()
    }

    func add(_ alarm: Alarm) {
        alarms.append(alarm)
        sortAlarms()
    }

    private func sortAlarms() {
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    func delete(at offsets: IndexSet) {
        alarms.remove(atOffsets: offsets)
    }

    func toggle(_ alarm: Alarm) {
        if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[idx].enabled.toggle()
        }
    }

    func checkAlarms() -> Alarm? {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let weekday = cal.component(.weekday, from: now) // 1=Sun, 7=Sat

        for i in alarms.indices {
            let alarm = alarms[i]
            guard alarm.enabled,
                  alarm.hour == hour,
                  alarm.minute == minute,
                  alarm.id != lastFiredAlarmID else { continue }

            // Check repeat days
            if !alarm.repeatDays.isEmpty && !alarm.repeatDays.contains(weekday) {
                continue
            }

            // Fire this alarm
            lastFiredAlarmID = alarm.id

            // Disable one-time alarms after firing
            if alarm.repeatDays.isEmpty {
                alarms[i].enabled = false
            }

            return alarm
        }

        // Reset lastFired when minute changes
        if let lastID = lastFiredAlarmID,
           let last = alarms.first(where: { $0.id == lastID }),
           !(last.hour == hour && last.minute == minute) {
            lastFiredAlarmID = nil
        }

        return nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Alarm].self, from: data) else { return }
        alarms = decoded.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }
}
