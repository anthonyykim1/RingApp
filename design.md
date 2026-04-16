# RingApp — Custom Notification Vibration for AIZO RING (Rogbid SR10)

## Goal

Replace the AIZO Ring app with a custom iOS app that vibrates the ring for any iPhone notification the user selects — not just phone calls.

## Background

The Rogbid SR10 ("AIZO RING") is a BLE health ring. The official AIZO Ring app (`com.eiot.be.ring`) only triggers vibration for incoming phone calls, despite the hardware supporting vibration for any event. Through reverse-engineering the Android APK, the BLE protocol has been fully decoded.

## BLE Protocol (Confirmed Working)

### Connection
- **Device name:** "AIZO RING"
- **Service UUID:** FE02
- **Write characteristic:** 0101 (Write)
- **Notify characteristic:** 010A (Notify)

### Packet Framing

Every command must be wrapped in a packet:

```
[Length (2B)] [Header (2B)] [SN (2B)] [Payload (NB)] [CRC16 (2B)]
```

- **Length** (big-endian): byte count of `payload + CRC`
- **Header**: `0x9240` (fixed for app→ring single packets: source=APP, dest=TERMINAL, ver=2, type=1, ack=0, pkgType=single, rfu=0)
- **SN** (big-endian): incrementing sequence number (0x0000, 0x0001, ...)
- **Payload**: the command bytes
- **CRC16**: CRC-CCITT variant over the payload bytes

### CRC16 Algorithm (from decompiled source)

```swift
func crc16(_ data: [UInt8]) -> UInt16 {
    var crc: UInt16 = 0xFFFF
    for byte in data {
        crc = ((crc << 8) | (crc >> 8)) & 0xFFFF
        crc ^= UInt16(byte)
        crc ^= (crc & 0xFF) >> 4
        crc ^= (crc << 12) & 0xFFFF
        crc ^= ((crc & 0xFF) << 5) & 0xFFFF
    }
    return crc
}
```

### Vibration Commands (Confirmed Working)

**Trigger vibration (vibratePhone):**
- Payload: `[0x10, 0x08, type]`
- Response expected: `[0x11, 0x08]`
- type=1 (app event) — **confirmed working**
- type=5 (notification event) — untested

**Test vibration (sendExperience):**
- Payload: `[0x16, 0x10, type, 0xFF]`
- Response expected: `[0x16, 0x20]`
- type=4 with 0xFF — **confirmed working**

**Set vibration switch (setStatus):**
- Payload: `[0x16, 0x11, count, type1, status1, type2, status2, ...]`
- Response expected: `[0x16, 0x21]`
- type values: 1=app, 2=health, 3=alarm, 4=callin, 5=notification, 6=care
- status: 1=on, 0=off

### Example Framed Packet

Trigger app vibration (type=1):
```
Payload:  10 08 01
CRC16:    16 77
Framed:   00 05 92 40 00 00 10 08 01 16 77
          [len ] [hdr ] [sn  ] [payload] [crc ]
```

## Architecture

### App Structure

Single iOS app with two main components:

1. **BLE Manager** — connects to the ring, maintains connection, sends vibration commands
2. **Notification Monitor** — monitors incoming iOS notifications, filters by user selection

### Notification Monitoring Approach

**Using `UNUserNotificationCenter` with Notification Service Extension:**

- A **Notification Service Extension** intercepts all push notifications before they're displayed
- The extension communicates with the main app via **App Groups** shared UserDefaults
- When a notification arrives from an enabled app, the main app sends the vibration command

**Alternative: ANCS approach (simpler):**

The ring hardware already supports ANCS (Apple Notification Center Service) — it asked for notification permission when pairing. However, ANCS gives notification data TO the accessory, it doesn't let our app control what happens. Since we need custom filtering, we'll use the extension approach.

**Simplest viable approach: Background notification observation**

iOS doesn't let third-party apps directly observe other apps' notifications. The realistic approaches are:

1. **Notification Service Extension** — only works for push notifications (not local notifications from all apps)
2. **CTCallCenter / CallKit** — for phone calls specifically
3. **Screen time / Focus filter APIs** — limited
4. **The ANCS route** — let the ring receive ALL notifications via ANCS, and our app only needs to tell the ring which types to vibrate for

**Recommended: Hybrid ANCS + Direct Control**

Since the ring already has ANCS support built into its firmware:
- Let the ring pair with iPhone and receive ANCS notification data
- Our app connects to the ring's custom FE02 service
- Use `setStatus` command to enable vibration for notification types (app=1, notification=5)
- The ring firmware may already vibrate when it receives ANCS notifications IF vibration is enabled for that type
- Our app's role: manage the BLE connection and send the setStatus commands to configure which notification types trigger vibration

If ANCS-based vibration doesn't work (i.e., the ring firmware only vibrates on explicit commands, not ANCS events), fall back to:
- **Notification Service Extension** for push notifications
- **CallKit** for phone calls
- Direct vibration command for each event

### Screens

#### 1. Main Screen — Connection Status
- Ring name, connection status (connected/disconnected/searching)
- Battery level (if available via BLE)
- "Connect" / "Disconnect" button
- Last vibration sent timestamp

#### 2. Notification Settings Screen
- List of notification categories with toggles:
  - Phone Calls
  - Messages / SMS
  - App Notifications (with per-app picker)
- When toggled, sends `setStatus` command to ring
- Per-app picker: shows installed apps, user toggles which trigger vibration

#### 3. Test Screen
- "Test Vibration" button — sends test vibration command
- Vibration type picker (for debugging)
- Log of sent commands and responses

### Data Persistence

- **UserDefaults**: enabled notification types, selected apps
- **Keychain**: not needed (no auth)
- **App Groups**: shared container for extension ↔ app communication

### Background Operation

The app must maintain BLE connection in the background:
- `UIBackgroundModes`: `bluetooth-central`
- CoreBluetooth state preservation and restoration
- Reconnect automatically when ring comes back in range

## Implementation Plan — Status

### Milestone 1: BLE Connection + Test Vibration — COMPLETE
- Xcode project setup (SwiftUI, iOS 17+) via XcodeGen
- `BLEManager` class: scan, connect, discover services
- `PacketFramer`: header + SN + CRC16
- Start/stop vibration control (call state commands)
- Custom vibration patterns (N buzzes × duration with pauses)
- Connection status display with animated icon

### Milestone 2: ANCS / Notification Type Configuration — COMPLETE (partial)
- Tested `setStatus` — only Phone Calls (type=4) triggers ANCS auto-vibration
- Other types (app, notification, etc.) do NOT auto-vibrate via ANCS
- The Android app actively sends vibratePhone per notification; ring never auto-vibrates for non-calls
- `setVibrate` and `getVibrate` tested — no observable effect on vibration behavior

### Milestone 3: Notification Forwarding — COMPLETE (via Shortcuts)
- Notification Service Extension approach FAILED (only intercepts own app's notifications)
- Polling getDeliveredNotifications() FAILED (only returns own app's notifications)
- **Solution: iOS Shortcuts automation + App Intent**
  - App exposes "Vibrate Ring" App Intent with configurable buzzes/duration/pause
  - User creates Shortcuts automation: "When I get a message" → Vibrate Ring
  - Works for iMessage/SMS, personal email, alarms
  - Cannot cover WhatsApp, Slack, Intune Outlook (iOS platform limitation)

### Milestone 4: Background & Reliability — COMPLETE
- CoreBluetooth state restoration (willRestoreState)
- Auto-reconnect using saved peripheral UUID (no rescan needed)
- 30-second BLE keepalive timer to prevent idle disconnection
- `bluetooth-central` background mode

### Milestone 5: Polish — COMPLETE
- App icon (blue/white ring design)
- Settings persistence (UserDefaults for vibration type toggles)
- Custom vibration patterns working (start/stop with configurable timing)
- Notification settings view with Shortcuts setup instructions
- Battery level display on Ring tab (requested on connect via getBattery command)
- Alarms tab: multiple alarms, repeat days, per-alarm vibration count, persisted in UserDefaults
- App Intent runs silently without foregrounding the app

## Technical Decisions

- **SwiftUI** for UI (modern, simple screens)
- **CoreBluetooth** for BLE (standard iOS framework)
- **No server needed** — everything is local on-device
- **iOS 17+** minimum (latest APIs, simplifies development)
- **iPhone only** (ring is an iPhone accessory)

## Risks — Resolved

1. **ANCS + setStatus does NOT auto-vibrate** for non-call events — CONFIRMED. Ring requires explicit commands. Solved via Shortcuts + App Intent.
2. **Background BLE reliability** — mitigated with 30-second keepalive timer + state restoration. Not perfect but significantly better.
3. **Notification Service Extension** — DOES NOT WORK for other apps' notifications. Only intercepts notifications sent to YOUR app's bundle ID. This was a fundamental misunderstanding.
4. **Ring firmware auth** — NO auth needed. Commands work immediately after connecting.

## Current Limitations (iOS Platform)

- No API to observe other apps' notifications (getDeliveredNotifications is app-scoped)
- Shortcuts message automation requires "Message Contains" field (can't match all messages cleanly)
- Shortcuts doesn't respect per-conversation "Hide Alerts"
- Shortcuts doesn't filter by SIM line
- Shortcuts can't trigger on WhatsApp/Slack/Instagram notifications
- Intune-managed Outlook blocks Shortcuts integration
- Accessory Notifications Framework is EU-only and requires manufacturer entitlements

## File Structure

```
RingApp/
├── project.yml                    # XcodeGen project spec
├── context.md                     # Full project context + session notes
├── design.md                      # This file
├── RingApp/
│   ├── RingAppApp.swift           # App entry, 4-tab TabView, App Intent registration
│   ├── VibrateIntent.swift        # App Intent for Shortcuts automation (openAppWhenRun=false)
│   ├── Info.plist                 # bluetooth-central background mode
│   ├── RingApp.entitlements       # App Groups
│   ├── Assets.xcassets/           # App icon
│   ├── BLE/
│   │   ├── BLEManager.swift       # CoreBluetooth manager, keepalive, reconnect
│   │   └── PacketFramer.swift     # Packet framing + CRC16
│   ├── Views/
│   │   ├── ConnectionView.swift   # Ring status, battery %, connect/disconnect
│   │   ├── AlarmView.swift        # Alarm list, add/edit/delete, repeat days
│   │   ├── TestView.swift         # Vibration testing, start/stop, patterns
│   │   └── NotificationSettingsView.swift  # Shortcuts setup, vibration config
│   └── Models/
│       ├── SettingsStore.swift    # UserDefaults for vibration type toggles
│       └── AlarmStore.swift       # Alarm model + persistence + time checking
└── NotificationService/           # NSE target (non-functional, kept for reference)
    ├── NotificationService.swift
    ├── NotificationService.entitlements
    └── Info.plist
```
