# RingApp — Full Session Context

## Project Goal

Build an iOS app that replaces the AIZO Ring app to enable custom notification vibrations on a Rogbid SR10 smart ring. The official app only vibrates for phone calls; we want vibration for any/all iPhone notifications the user selects.

## Hardware

- **Ring:** Rogbid SR10
- **App:** AIZO RING (com.eiot.be.ring) by Shenzhen eIoT Technology
- **Firmware:** 4.15.06
- **BLE device name:** "AIZO RING"

## BLE Protocol (Reverse-Engineered & Confirmed)

### Service & Characteristics

| Service | Characteristic | Properties | Purpose |
|---------|---------------|------------|---------|
| FE02 | 0101 | Write | Send commands to ring |
| FE02 | 010A | Notify | Receive responses from ring |
| FF12 | FF15 | Read, Write Without Response | OTA firmware updates (not needed) |
| FF12 | FF14 | Notify | OTA notifications (not needed) |
| 180D | 0001 | Write | Heart rate (not needed) |
| 1812 | - | - | HID service |

### Packet Framing

Every command must be wrapped:

```
[Length (2B big-endian)] [Header (2B)] [SN (2B big-endian)] [Payload (NB)] [CRC16 (2B)]
```

- **Length**: byte count of `payload + CRC` (NOT total packet length)
- **Header**: `0x9240` (fixed value — source=APP(2), dest=TERMINAL(1), ver=2, type=1, ack=0, pkgType=single(0), rfu=0)
- **SN**: incrementing sequence number starting at 0x0000
- **Payload**: command bytes
- **CRC16**: computed over payload bytes only

### CRC16 Algorithm

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

### Vibration Commands

**Trigger vibration (vibratePhone):**
- Payload: `[0x10, 0x08, type]`
- Expected response: `[0x11, 0x08]`
- type=1 (app event) — **CONFIRMED WORKING**
- type=4 (call) — did NOT work from nRF Connect
- type=5 (notification) — untested

**Test vibration (sendExperience):**
- Payload: `[0x16, 0x10, type, 0xFF]`
- Expected response: `[0x16, 0x20]`
- type=4 with 0xFF — **CONFIRMED WORKING**

**Set vibration on/off (setStatus):**
- Payload: `[0x16, 0x11, count, type1, status1, type2, status2, ...]`
- Expected response: `[0x16, 0x21]`
- Vibration types: 1=app, 2=health, 3=alarm, 4=callin, 5=notification, 6=care
- Status: 1=on, 0=off

### Confirmed Working Framed Packets (tested in nRF Connect)

```
# Test vibration (sendExperience, type=4):
000692400000161004FF29A9

# App vibration (vibratePhone, type=1):
00059240000010080116770

# Breakdown of app vibration packet:
# 0005     = length (5 bytes: 3 payload + 2 CRC)
# 9240     = header
# 0000     = sequence number 0
# 100801   = payload (vibratePhone, type=1)
# 1677     = CRC16 of payload
```

### Vibration Event Type Constants (from decompiled BeVibrateHelper.java)

```
VIBRATE_TYPE_APP_EVENT = 1
VIBRATE_TYPE_HEALTH_EVENT = 2
VIBRATE_TYPE_ALARM_EVENT = 3
VIBRATE_TYPE_CALLIN_EVENT = 4
VIBRATE_TYPE_NOTIFICATION_EVENT = 5
VIBRATE_TYPE_CARE_EVENT = 6
```

### Vibration Switch Type Constants

```
VIBRATE_SWITCH_TYPE_ALL = 0
VIBRATE_SWITCH_TYPE_APP = 1
VIBRATE_SWITCH_TYPE_CALL_IN = 4
```

## What Was Tested

1. Connected to ring via nRF Connect on iPhone
2. Ring asked to pair (accepted) and asked for notification access (allowed — this enables ANCS)
3. Tried raw byte writes to 0101 characteristic — simple payloads like `01`, `FF` did NOT work
4. Decompiled Android APK (com.eiot.be.ring v2.2.0) using JADX
5. Found vibration commands in `BeVibrateHelper$vibratePhone$result$1.java` and `BeVibrateHelper$sendExperience$result$1.java`
6. Found packet framing in `BtPackage.java` and CRC16 in `CRC16.kt` (package `oty3cKVwhieXiYRHB`)
7. Computed full framed packets with Python, tested in nRF Connect
8. **sendExperience (type=4) and vibratePhone (type=1) CONFIRMED WORKING**

## Decompiled Source Locations

All decompiled Java source is at: `~/Downloads/aizo_decompiled/sources/com/eiot/`

Key files:
- `com/eiot/be/ring/be/BeVibrateHelper.java` — vibration type constants, high-level vibration methods
- `com/eiot/be/ring/be/BeVibrateHelper$vibratePhone$result$1.java` — vibratePhone command: `{0x10, 0x08, type}`
- `com/eiot/be/ring/be/BeVibrateHelper$sendExperience$result$1.java` — sendExperience command: `{0x16, 0x10, type, 0xFF}`
- `com/eiot/be/ring/be/BeVibrateHelper$setStatus$result$1.java` — setStatus command: `{0x16, 0x11, count, ...pairs}`
- `com/eiot/be/ring/be/BtHelper.java` — BLE connection manager, wraps AizoBtCommend
- `com/eiot/aizo/core/BtPackage.java` — packet framing (length + header + SN + payload + CRC)
- `com/eiot/aizo/ble/lib/BleDevice.java` — low-level BLE device (GATT write, service discovery)
- `oty3cKVwhieXiYRHB/mldI7uGmhVJQWi.java` — CRC16 implementation (originally CRC16.kt)
- `com/eiot/aizo/util/ByteUtil.java` — byte array concatenation utility

## App Architecture (from design.md)

### Milestones

1. **BLE Connection + Test Vibration** — scan, connect, send vibration on button press
2. **ANCS / Notification Type Config** — try setStatus to enable notification vibration types; test if ring auto-vibrates via ANCS
3. **Notification Service Extension** (if ANCS auto-vibrate doesn't work) — intercept push notifications, filter by app, send vibration commands
4. **Background & Reliability** — CoreBluetooth state restoration, auto-reconnect
5. **Polish** — icon, settings persistence, vibration patterns

### Tech Stack
- SwiftUI, iOS 17+, iPhone only
- CoreBluetooth for BLE
- No server needed — everything local
- UserDefaults for settings
- App Groups for extension ↔ app communication (if extension needed)
- UIBackgroundModes: bluetooth-central

### Key Design Decisions
- App replaces AIZO entirely (user confirmed they don't need health tracking features)
- User wants vibration for every notification, OR ability to pick/choose per app
- The ring supports ANCS — it requested and was granted notification access
- Milestone 2 tests whether just enabling vibration types via setStatus makes the ring auto-vibrate on ANCS notifications (would be the simplest solution)

## Directory Structure

- Project directory: `~/OffCloud/M-A-Project/RingApp/`
- Design doc: `~/OffCloud/M-A-Project/RingApp/design.md`
- This context file: `~/OffCloud/M-A-Project/RingApp/context.md`

## What Was Built (Session 1 — 2026-04-09)

### Completed
- Full SwiftUI iOS app with 3-tab UI (Ring, Notifications, Test)
- BLE connection to ring via FE02 service (write: 0101, notify: 010A)
- Packet framing with CRC16 — all confirmed working
- Start/stop vibration control using call state commands (type=1 start, type=2 stop)
- Custom vibration patterns: configurable buzzes, duration, pause
- Auto-reconnect with saved peripheral UUID (no need to forget from Bluetooth settings)
- 30-second BLE keepalive to prevent idle disconnection
- CoreBluetooth state restoration for background persistence
- App Intent ("Vibrate Ring") exposed to iOS Shortcuts
- iMessage/SMS vibration via Shortcuts automation → App Intent
- App icon (blue background with white ring "O")
- Notification Service Extension target (created but not functional — see findings below)
- Alarms tab: multiple alarms with repeat days, per-alarm vibration count (default 10), checked via BLE keepalive
- Battery level indicator on Ring tab (reads via custom command [0x38, 0x38, 0x02], response ACK [0x78, 0x78])
- App Intent runs without bringing app to foreground (openAppWhenRun = false)

### Key Protocol Findings
- **vibratePhone payload [0x10, 0x08, type]** uses call state, not event types:
  - type=1 (RINGING) = START vibrating
  - type=2 (OFFHOOK) = STOP vibrating
  - type=3 (IDLE) = STOP vibrating
- **sendExperience [0x16, 0x10, type, intensity]** — very short buzz, intensity byte has no visible effect
- **setStatus [0x16, 0x11, ...]** — configures ANCS vibration types but only Phone Calls (type=4) actually works via ANCS
- **setVibrate [0x16, 0x13, ...]** — configures high/low values per type, but changing values had no observable effect on vibration
- **getVibrate [0x16, 0x14, type]** — reads current config, defaults were all zeros
- **getBattery [0x38, 0x38, 0x02]** — response ACK is [0x78, 0x78, 0x02, battery%, mode, ...]; battery% at payload byte index 3 (packet byte 9)
- The Android AIZO app uses NotificationListenerService to actively send vibratePhone commands per notification — the ring never auto-vibrates for non-call ANCS events

### iOS Notification Limitations Discovered
- **UNUserNotificationCenter.getDeliveredNotifications()** — only returns YOUR app's notifications, not other apps'
- **Notification Service Extension** — only intercepts YOUR app's push notifications, not other apps'
- **No iOS API exists** for third-party apps to observe other apps' notifications
- **Accessory Notifications Framework** (iOS 26.3+) — EU-only, requires restricted entitlements from Apple, designed for hardware manufacturers only
- **Shortcuts automation** is the only viable path for non-call notification vibration

### What Works
| Source | Works? | How |
|--------|--------|-----|
| Phone calls | Yes | ANCS automatic (ring firmware) |
| iMessage / SMS | Yes | Shortcuts automation → App Intent |
| Personal email (Mail app) | Yes | Shortcuts automation (untested) |
| Alarm stopped/snoozed | Yes | Shortcuts automation (untested) |
| Outlook (Intune-managed) | No | Blocked by Intune from Shortcuts |
| WhatsApp, Slack, etc. | No | No iOS API or Shortcuts trigger |

### Known Issues
- Shortcuts "When I get a message" requires "Message Contains" filter (can't be blank) — workaround: enter a space
- Shortcuts shows a "Running your automation" notification banner when automation runs — **no way to suppress** for "When I get a message" trigger. The "Notify When Run" toggle (iOS 15.4+) does NOT appear for message-based automations. Only options are Run Immediately / Run After Confirmation / Don't Run. Screen Time App Limits trick (0 min on Shortcuts) is unreliable and may block automations entirely.
- Hide Alerts per-conversation in Messages is not respected by Shortcuts automations
- Cannot filter by SIM line in Shortcuts
- **Ring buzzes on BLE reconnect** — confirmed firmware behavior during ANCS re-handshake. Cannot be prevented from app side. stopVibration sent immediately after "Ring ready!" but arrives after the buzz completes. Only triggers when BLE connection is re-established after a drop (e.g. walking out of range).
- setStatus with non-call types enabled may cause unexpected buzzes on reconnect — keep only Phone Calls enabled
- Alarms have ~30 second granularity (checked on dedicated 30s alarm timer)

## Future Session Checklist — Check These First

**IMPORTANT: At the start of any new session working on this app, check for these iOS/platform updates:**

1. **Shortcuts "When I get a notification" trigger** — Does iOS now offer a Shortcuts automation trigger for arbitrary app notifications? This would solve WhatsApp/Slack/Outlook. Search: "iOS Shortcuts notification trigger any app"

2. **Shortcuts Hide Alerts awareness** — Can Shortcuts automations now respect per-conversation "Hide Alerts" settings in Messages? Search: "iOS Shortcuts message automation hide alerts filter"

3. **Shortcuts notification suppression** — Can the "automation ran" notification be suppressed natively now? Search: "iOS Shortcuts suppress automation notification"

4. **Accessory Notifications Framework availability** — Has Apple made the AccessoryNotifications framework available globally (not just EU)? Are the entitlements obtainable? Search: "AccessoryNotifications framework iOS availability entitlements"

5. **NotificationListenerService equivalent** — Has Apple introduced any API for apps to observe other apps' notifications? Search: "iOS notification listener API third party"

6. **Shortcuts Message Contains workaround** — Can the "Message Contains" field be left blank now, or is there a better wildcard? Search: "iOS Shortcuts message contains any workaround"

## What Was Built (Session 2 — 2026-04-15)

### Phantom Vibration Investigation & Fix
- **Root cause identified:** ring firmware buzzes during ANCS re-handshake on every BLE reconnect. This is firmware-level behavior that cannot be prevented from the app side.
- **Secondary cause identified and fixed:** iOS was suspending the app every 7-9 minutes, causing frequent reconnects (and thus phantom buzzes). Fixed by adding a background location session (CoreLocation, `kCLLocationAccuracyThreeKilometers`, `distanceFilter = CLLocationDistanceMax`).
- **Keepalive changed:** replaced `getBattery` every 30s with `getVibrate` every 2 minutes. `getBattery` was confirmed to intermittently trigger firmware vibration. `getVibrate` (read-only config query `[0x16, 0x14, type]`) tested clean over 38+ minutes of continuous operation.
- **Battery timer:** separate 10-minute timer for battery reads. Battery also fetched once on connect.
- **Alarm timer:** independent 30s timer dedicated to alarm checks, decoupled from keepalive frequency.
- **stopVibration on connect:** sent immediately after "Ring ready!" to cut short any ANCS reconnect buzz. Acknowledged by firmware but arrives after buzz completes (~2s BLE write latency during ANCS handshake).
- **Reconnect backoff:** 3-second minimum interval between reconnect attempts to prevent storms.
- **Net result:** phantom buzzes eliminated during normal use (phone and ring in proximity). Only remaining trigger is physically leaving and returning to Bluetooth range, which causes an unavoidable ANCS reconnect buzz.

### Persistent Logging
- Millisecond timestamps with full date (`yyyy-MM-dd HH:mm:ss.SSS`)
- RX frames decoded: length, sequence number, command label (batteryResp, vibratePhoneAck, setStatusAck, etc.), payload hex
- Disconnect events include NSError domain/code (e.g. `CBErrorDomain code=6` = supervision timeout)
- `UNUserNotificationCenter.getDeliveredNotifications()` logged on each connect
- Persistent log file at `Documents/ringapp.log`, append-only, auto-rotation at 2MB
- **Copy Log** button in Test tab (copies file contents to clipboard without affecting the file)
- Previous `Share Full Log` (ShareLink with file URL) was found to delete/move the source file on share — replaced with clipboard copy

### Shortcuts Enhancements
- **Group chat suppression:** Recipients count via Split Text + Count Items. `Count Recipients in Shortcut Input` returns 1 (opaque object); must Split Text by New Lines first. 1:1 = 1 recipient, group = 2+. See `shortcuts.md`.
- **Per-conversation debounce (leading edge):** `VibrateRingIntent` accepts `debounceKey` (string) and `debounceSeconds` (int, default 0). BLEManager maintains `lastBuzzByKey: [String: Date]`. First text in a conversation buzzes; subsequent texts within the debounce window are skipped silently. No trailing-edge buzz (iOS app suspension makes deferred timers unreliable).
- **Intent reconnect retry:** if ring is disconnected when Shortcuts fires the intent, it calls `startScan()` and polls for up to 3 seconds before giving up.
- **Shortcuts notification suppression:** No known way to suppress "Running your automation" banners for message-based automations. The "Notify When Run" toggle does not appear for the "When I get a message" trigger. Shortcuts doesn't appear in Settings → Notifications. The Screen Time App Limits trick (0 min) is unreliable and may block automations entirely.

### Shortcut Input Sub-Properties (Message type, confirmed)
- **Name** — returns message body text (NOT conversation title). Not useful for conversation identification.
- **Recipients** — list of other participants' phone numbers, one per line (does NOT include you). Must Split Text by New Lines to count items.
- **Sender** — the person who sent the message.
- **Content** — message body text.

### Background Location
- Added `CoreLocation` background session to prevent iOS from suspending the app
- `kCLLocationAccuracyThreeKilometers` + `distanceFilter = CLLocationDistanceMax` — minimal battery impact
- `pausesLocationUpdatesAutomatically = false`
- Requires "Always Allow" location permission (iOS only shows "While Using" on first prompt; must change in Settings → Privacy → Location Services → RingApp)
- Added `location` to UIBackgroundModes in Info.plist
- Confirmed working: 38+ minutes continuous operation with zero suspension gaps (previously 7-9 minutes max)

### Alarm Sorting
- Alarms now sorted chronologically (by hour, then minute) on add and on load from UserDefaults

### Architecture Changes
- Three independent timers: alarm (30s), keepalive/getVibrate (120s), battery (600s)
- `CLLocationManagerDelegate` conformance added to BLEManager
- `persistLogLine` runs synchronously on MainActor (read→append→write atomically), replacing broken background DispatchQueue approach

## What Was Built (Session 3 — 2026-04-16)

### 30-Minute Phantom Buzz — Root Cause Found & Fixed
- **Symptom:** Ring buzzed exactly at :00 and :30 of every hour, regardless of activity or connection state.
- **Root cause:** The ring's **heart rate monitoring interval** was set to 30 minutes. The firmware vibrates when taking a measurement. This was NOT a sedentary reminder.
- **Fix:** `[0x22, 0x11, 0x00]` (setHeartRateInterval to 0) — ring responded with ACK `[0x21, 0x11, 0x01]` (success). Confirmed: no buzz at next :00 mark.
- **Discovery path:** Tried and ruled out: setSitRemind `[0x10, 0x06]` (no response), getSitRemind `[0x10, 0x16]` (no response), setStatus type=6/care (ACK but didn't stop buzz), setSedentaryConfig `[0x15, 0x1B]` (no response). Breakthrough came from querying `getHRInterval` `[0x22, 0x10]` which returned `0x1E` (30 minutes).

### New BLE Commands Discovered
- **getHRInterval** `[0x22, 0x10]` → response `[0x21, 0x10, interval, ...]` — query heart rate monitoring interval
- **setHRInterval** `[0x22, 0x11, value]` → response `[0x21, 0x11, result]` — set HR interval (0=disabled)
- **getSwitchConfig** `[0x38, 0x38, 0x01]` → response `[0x78, 0x78, 0x01, ...]` — ring feature switch states
- **getDeviceConfig** `[0x38, 0x38, 0x04]` → response `[0x78, 0x78, 0x04, ...]` — full device configuration (60+ bytes)
- **Unsolicited `0x7901` messages** — ring pushes health data (step counts/activity) on its own every 2-3 min

### Commands That Don't Work on This Firmware (v4.15.06)
- `[0x10, 0x06]` setSitRemind — silently ignored (no response)
- `[0x10, 0x16]` getSitRemind — silently ignored (no response)
- `[0x15, 0x1B]` setSedentaryConfig — silently ignored (no response)
- These are likely "watch" commands not implemented on the ring firmware variant.

### Shortcuts Debounce Fix
- **Bug:** debounceKey was set to Shortcut Input "Name" property, which returns the **message body text** (unique per message), not the conversation/sender identifier.
- **Fix:** Changed debounceKey to Shortcut Input "Sender" property, which returns a consistent per-person identifier.

### Test Tab Enhancements
- Added "Sedentary Reminder" section with buttons for: Read Setting, Disable Sedentary Reminder, Disable All (keep calls), Disable via 0x15 Config, Query Ring Config, Disable HR Monitoring
- RX decoder now labels: setSitRemindAck, getSitRemindResp, setSedentaryConfigAck

## User Preferences

- User is building this for personal use
- Xcode 26.3 installed
- iPhone Air with latest iOS
- Ring must be forgotten from iPhone Bluetooth settings before first app connection (not needed after — app saves peripheral UUID)
- User approved building the entire app in autonomous/yolo mode
- User has paid Apple Developer account
- Outlook is managed by Intune (blocks Shortcuts integration)
