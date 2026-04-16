import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var appVibration: Bool {
        didSet { defaults.set(appVibration, forKey: Keys.app) }
    }
    @Published var healthVibration: Bool {
        didSet { defaults.set(healthVibration, forKey: Keys.health) }
    }
    @Published var alarmVibration: Bool {
        didSet { defaults.set(alarmVibration, forKey: Keys.alarm) }
    }
    @Published var callVibration: Bool {
        didSet { defaults.set(callVibration, forKey: Keys.call) }
    }
    @Published var notificationVibration: Bool {
        didSet { defaults.set(notificationVibration, forKey: Keys.notification) }
    }
    @Published var careVibration: Bool {
        didSet { defaults.set(careVibration, forKey: Keys.care) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let app = "vibrate_app"
        static let health = "vibrate_health"
        static let alarm = "vibrate_alarm"
        static let call = "vibrate_call"
        static let notification = "vibrate_notification"
        static let care = "vibrate_care"
        static let initialized = "settings_initialized"
    }

    init() {
        if !defaults.bool(forKey: Keys.initialized) {
            defaults.set(true, forKey: Keys.app)
            defaults.set(false, forKey: Keys.health)
            defaults.set(true, forKey: Keys.alarm)
            defaults.set(true, forKey: Keys.call)
            defaults.set(true, forKey: Keys.notification)
            defaults.set(false, forKey: Keys.care)
            defaults.set(true, forKey: Keys.initialized)
        }
        appVibration = defaults.bool(forKey: Keys.app)
        healthVibration = defaults.bool(forKey: Keys.health)
        alarmVibration = defaults.bool(forKey: Keys.alarm)
        callVibration = defaults.bool(forKey: Keys.call)
        notificationVibration = defaults.bool(forKey: Keys.notification)
        careVibration = defaults.bool(forKey: Keys.care)
    }

    /// All vibration type/status pairs for the setStatus BLE command.
    var allPairs: [(type: UInt8, enabled: Bool)] {
        [
            (1, appVibration),
            (2, healthVibration),
            (3, alarmVibration),
            (4, callVibration),
            (5, notificationVibration),
            (6, careVibration),
        ]
    }
}
