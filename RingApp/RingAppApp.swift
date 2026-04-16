import SwiftUI
import AppIntents

@main
struct RingAppApp: App {
    @StateObject private var bleManager = BLEManager.shared
    @StateObject private var settings = SettingsStore()
    @StateObject private var alarmStore = AlarmStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                ConnectionView()
                    .tabItem {
                        Label("Ring", systemImage: "circle.circle")
                    }
                AlarmView()
                    .tabItem {
                        Label("Alarms", systemImage: "alarm")
                    }
                NotificationSettingsView()
                    .tabItem {
                        Label("Notifications", systemImage: "bell")
                    }
                TestView()
                    .tabItem {
                        Label("Test", systemImage: "waveform")
                    }
            }
            .environmentObject(bleManager)
            .environmentObject(settings)
            .environmentObject(alarmStore)
            .task {
                RingAppShortcuts.updateAppShortcutParameters()
                bleManager.alarmStore = alarmStore
            }
        }
    }
}
