# RingApp

iOS app for controlling AIZO RING (Rogbid SR10) smart ring vibrations via BLE. iOS-only — no server,
no deploy.

**History document: `HISTORY.md`** — newest first, one dated entry per episode.

## Project Structure

- `RingApp/` — main app target (SwiftUI): `BLE/`, `Models/`, `Views/`, `VibrateIntent.swift` (Shortcuts)
- `NotificationService/` — notification service extension
- `project.yml` — XcodeGen spec; `RingApp.xcodeproj` is also committed (see `OPEN.md` for which is authoritative)
- App group `group.com.tonykim.RingApp`; deployment target iOS 17.0; bundle id `com.tonykim.RingApp`

## Key Technical Details

- **BLE vibration protocol:** `vibratePhone [0x10, 0x08, type]` where type=1=start, type=2=stop.
- **HR monitoring disable:** `setHeartRateInterval(0)` (sends `[0x22, 0x11, 0x00]`) runs in the connect
  handshake at `BLEManager.swift:735`, right after `stopVibration()`. Without it the ring firmware buzzes
  every ~30 min during HR measurement. **Don't remove** — silent failures look like "random phantom
  vibrations." (Line re-measured 2026-09-12; it had drifted from 653.)
- **Background persistence:** the background location session prevents iOS suspension. **Load-bearing —
  do not drop.** It is what stops phantom buzzes and missed buzzes, not just alarms. See `battery.md`.
- **Timers:** keepalive/getVibrate (120s, always); alarm check (30s, only when an enabled alarm exists);
  battery read on connect + app foreground (no periodic poll). Disconnected scan is bounded (12s window +
  15→120s backoff), not continuous. See `battery.md`.
- **Shortcuts debounce:** uses the Sender property (not Name) as `debounceKey`.
- **"Running your automation" banner — a closed platform dead end. Do not re-test.** No suppression
  exists on iOS (through iOS 26) for message-trigger automations: Apple privacy block (`Notify When Run`
  hidden, Shortcuts absent from Notifications). **Focus mode does NOT work either** — falsified on-device
  2026-05-28 (iOS 26 / iPhone Air): Shortcuts isn't listable in Focus "Silence Notifications From", and an
  allowlist + Time Sensitive OFF still leaves the visual pop-up. The only escape is moving message
  detection off-device (Mac — `mac-migration-plan.md`). Detail: `shortcuts.md`.
- ⭐ **The invariant that dead end bought: a platform dead end stays dead. Stop iterating and route
  around it.** It ate hours, then Focus was *assumed* to be the fix, then Focus itself was falsified.

## Build and commit

Open `RingApp.xcodeproj` in Xcode. `./scripts/commit.sh "msg"` is git add + commit + push.

**Repo delta — a commit here means a state verified on hardware.** Don't commit just to test: build in
Xcode against the synced working tree first. Working-tree edits on the Mac Studio auto-sync to the
MacBook, which is where device builds happen.

## iOS protocol — deltas from `~/OffCloud/claude-setup/IOS_AGENT_STACK.md`

That file carries the universal protocol (verification workflow, AX identifier convention, forbidden
patterns, the 3-attempt cap, `/goal` pairing, the required task summary, and Mac Studio as the source of
truth for `.xcodeproj` edits). **Read it before any iOS work here.** Only what is different in Ring:

- ⛔ **Bluetooth LE is unavailable in the iOS Simulator** — `CBCentralManager.state` returns
  `.unsupported`. Every BLE flow (scan, connect, vibration command, HR-monitor disable, keepalive,
  battery read) must be exercised on a real iPhone with the ring nearby. **This is where Ring deviates
  hardest from a typical iOS app: most of its core surface is device-only**, and a Maestro flow that
  depends on BLE state cannot pass in the simulator.
- **Background location** behaves differently in sim — it doesn't suspend the same way, so "did we stay
  alive in the background" is a device-only question.
- **NotificationService** runs against real APNs payloads: device + a real push, not simulator tricks.
- **App Group** writes work in sim, but cross-process visibility (main app ↔ NotificationService) is only
  representative on device.
- **Shortcuts / Siri intent invocation DOES work in the simulator** — but the running-automation
  banner's behavior there is iOS-version-dependent and proves nothing about the device. ⛔ Do not
  re-research suppressing it; see the dead end above.
- **UI-only surfaces** (button layout, settings screens, view state independent of BLE) are fine in the
  simulator and faster there.
- **Never claim BLE behavior works without exercising it on device** — this repo's form of the global
  "no 'this should work'" rule.
- **The task summary must name the device, iOS version, and whether the ring was connected** — "iPhone
  Air, iOS 26, ring connected y" — because "tested" is meaningless here without it.
- **Maestro:** `appId: com.tonykim.RingApp`; flows go at `maestro/bugs/<short-name>.yaml`. ⚠️ No
  `maestro/` directory exists yet — the first flow creates it. No snapshot-test dependency is wired in
  either; adding `swift-snapshot-testing` would be a structural Xcode change.

## Project docs to read before specific changes

- BLE protocol / connect handshake / HR-monitor disable → `context.md`
- Shortcuts / VibrateIntent / the running-automation banner → `shortcuts.md`
- Battery, scan backoff, why location is load-bearing → `battery.md`
- Visual / interaction design → `design.md`
- Mac-build migration history → `mac-migration-plan.md`
