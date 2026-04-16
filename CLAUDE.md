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
- **HR monitoring disable:** Send `[0x22, 0x11, 0x00]` on connect to prevent firmware buzz every 30 min
- **Background persistence:** Background location session prevents iOS suspension
- **Three timers:** alarm check (30s), keepalive/getVibrate (120s), battery (600s)
- **Shortcuts debounce:** Uses Sender property (not Name) as debounceKey

## Build

Open `RingApp.xcodeproj` in Xcode. Requires iOS 17+ target. App group: `group.com.tonykim.RingApp`.
