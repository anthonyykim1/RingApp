import AppIntents

struct VibrateRingIntent: AppIntent {
    static var title: LocalizedStringResource = "Vibrate Ring"
    static var description: IntentDescription = "Sends a vibration pattern to the connected AIZO RING."
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Buzzes", default: 3)
    var buzzes: Int

    @Parameter(title: "Buzz Duration (ms)", default: 800)
    var buzzDuration: Int

    @Parameter(title: "Pause Between (ms)", default: 0)
    var pauseBetween: Int

    @Parameter(title: "Debounce Key", default: "")
    var debounceKey: String

    @Parameter(title: "Debounce Seconds", default: 0)
    var debounceSeconds: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let manager = BLEManager.shared
        let key = debounceKey.isEmpty ? "_default" : debounceKey
        if !manager.shouldBuzz(key: key, debounceSeconds: debounceSeconds) {
            return .result(value: "Debounced")
        }
        if manager.connectionState != .connected {
            manager.startScan()
            let deadline = Date().addingTimeInterval(3.0)
            while manager.connectionState != .connected && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if manager.connectionState != .connected {
                return .result(value: "Ring not connected")
            }
        }
        manager.sendRepeatedVibration(
            buzzes: buzzes,
            buzzMs: buzzDuration,
            pauseMs: pauseBetween
        )
        // Wait for vibration to complete before returning
        let totalMs = buzzes * buzzDuration + max(0, buzzes - 1) * pauseBetween
        try? await Task.sleep(for: .milliseconds(totalMs + 500))
        return .result(value: "Vibrated \(buzzes)x")
    }
}

struct RingAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: VibrateRingIntent(),
            phrases: [
                "Vibrate my ring with \(.applicationName)",
                "Buzz my ring with \(.applicationName)"
            ],
            shortTitle: "Vibrate Ring",
            systemImageName: "circle.circle.fill"
        )
    }
}
