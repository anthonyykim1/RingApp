# RingApp

iOS app for controlling AIZO RING (Rogbid SR10) smart ring vibrations via BLE.

## Project Structure

- `RingApp/` — main app target (SwiftUI)
  - `BLE/` — Bluetooth LE communication with ring
  - `Models/` — data models
  - `Views/` — SwiftUI views
  - `VibrateIntent.swift` — Shortcuts integration
- `NotificationService/` — notification service extension
- `RingApp.xcodeproj` — Xcode project
- `context.md` — detailed BLE protocol docs, session checklist
- `design.md` — app design notes
- `shortcuts.md` — Shortcuts integration docs

## Key Technical Details

- **BLE vibration protocol:** `vibratePhone [0x10, 0x08, type]` where type=1=start, type=2=stop
- **HR monitoring disable:** `setHeartRateInterval(0)` (sends `[0x22, 0x11, 0x00]`) runs in the connect handshake at `BLEManager.swift:653` right after `stopVibration()`. Without this, the ring firmware buzzes every ~30 min during HR measurement. Don't remove — silent failures look like "random phantom vibrations."
- **Background persistence:** Background location session prevents iOS suspension
- **Three timers:** alarm check (30s), keepalive/getVibrate (120s), battery (600s)
- **Shortcuts debounce:** Uses Sender property (not Name) as debounceKey
- **"Running your automation" banner:** No native suppression on iOS 17/18 for message-trigger automations (Apple privacy block — `Notify When Run` toggle is hidden, Shortcuts has no Notifications entry). Focus mode allow-list is the only working workaround. Don't re-research this — see `shortcuts.md` § "Suppressing the running-automation banner".

## Build

Open `RingApp.xcodeproj` in Xcode. Requires iOS 17+ target. App group: `group.com.tonykim.RingApp`.
