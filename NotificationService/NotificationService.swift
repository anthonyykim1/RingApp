import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    private let suiteName = "group.com.tonykim.RingApp"

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        // Signal the main app to vibrate the ring
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.set(Date().timeIntervalSince1970, forKey: "lastNotificationTimestamp")
            defaults.set(request.content.title, forKey: "lastNotificationTitle")
            defaults.synchronize()
        }

        // Post a Darwin notification to wake the main app
        let name = "com.tonykim.RingApp.notification" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil, nil, true
        )

        // Pass the notification through unmodified
        contentHandler(request.content)
    }

    override func serviceExtensionTimeWillExpire() {
        // No-op — we already signaled on didReceive
    }
}
