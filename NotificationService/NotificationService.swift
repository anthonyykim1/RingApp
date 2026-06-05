import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    // NOTE: The buzz-on-message path runs entirely through the iOS Shortcuts
    // automation → VibrateRingIntent → BLEManager (see shortcuts.md). The main app
    // never observed the App Group / Darwin signals this extension used to post, so
    // those writes were dead weight on every notification and have been removed.
    // This extension now just passes the notification through unmodified.
    // (Removing the target entirely is a further win, but that's an Xcode
    // structural change to be done on the Mac Studio.)

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        contentHandler(request.content)
    }
}
