# RingApp — Battery / Power Notes

Power-drain investigation and the optimizations made for it. Read before touching the
scan/reconnect loop, the keepalive/alarm/battery timers, the background location session,
or log persistence.

## The load-bearing constraint — DO NOT drop background location

The background `CLLocationManager` session (`BLEManager.startBackgroundLocation`) is **not**
there for alarms. It exists to stop iOS suspending the app, which causes two regressions:

1. **Phantom buzzes.** Suspension → BLE reconnect → ANCS re-handshake → the ring buzzes.
   This was the #1 bug fought across Sessions 2–3.
2. **Missed/late buzzes.** A warm connection lets `VibrateRingIntent` find `.connected` and
   fire instantly. Suspended → the intent must cold-start BLE and connect inside its 3s
   window, which BLE rarely makes from cold.

Evidence it's required: `bluetooth-central` background mode + CoreBluetooth state restoration
were *already enabled* when the app was still being suspended every 7–9 min. Location is what
fixed it. So "rely on BLE restoration instead of location" was already the config that failed.
It's also the cheap flavor: 3 km accuracy (cell/Wi-Fi, no GPS) + max distance filter.
**Leave it on.** The only way to beat it is a deliberate on-device A/B (disable location, watch
the log for suspension gaps + phantom buzzes over a full day) — treat as unlikely to work.

## Optimizations landed (Session 4 — 2026-06-05)

All target *avoidable* waste; none touch the buzz path, keepalive, handshake, or location.

1. **Bounded the disconnected scan** (`BLEManager.startScan` step 3 + `scheduleScanTimeout`/
   `stopScanTimeout`). The fallback `scanForPeripherals(withServices: nil)` used to scan
   forever — the main "drains when disconnected, constantly searching" cause. Now scans a 12s
   window, then backs off `15→30→60→120s` between retries. Kept `withServices: nil` (ring is
   matched by name in `didDiscover` and may not advertise FE02 — don't switch the filter
   unverified). The cheap pending-`connect()` reconnect path (known peripheral) is untouched,
   so a known ring still auto-reconnects instantly.
2. **Dropped the 10-min battery poll.** Removed `batteryTimer`/`batteryInterval`. Battery is
   read on connect and on app foreground (`RingAppApp` `scenePhase == .active`). Bonus: one
   fewer recurring `getBattery`, which can intermittently trigger a firmware buzz.
3. **Gated the 30s alarm timer.** `refreshAlarmTimer()` only runs the timer when an enabled
   alarm exists (none, in normal use → zero 30s wakeups). Starts/stops via `AlarmStore`'s new
   `onAlarmsChanged` callback. Alarms still fully work if added.
4. **Stripped the dead NotificationService path.** Removed the per-notification App Group
   writes + `synchronize()` + Darwin post — nothing in the main app ever listened for them
   (buzz-on-message runs through Shortcuts, not the NSE). Now a passthrough. Fully removing
   the NSE target is a further win but is a Mac-Studio Xcode structural change.
5. **Append-only logging.** `persistLogLine` appends one line via `FileHandle` instead of
   read+rewrite-whole-file every line; full trim runs only every ~100 lines.

## Behavioral change to know

If the ring has no resolvable system identifier (`ringPeripheral == nil`, e.g. never paired
this session) **and** is absent a long time, reconnect-via-scan can now lag up to ~120s. In the
normal post-pairing case this never applies (pending-`connect()` reconnects immediately), and
tapping **Connect** forces an immediate 12s scan.

## Verification status

- ✅ Compiles clean — `build_sim` on iPhone 17 Pro / iOS 26.3, zero warnings/errors (2026-06-05).
- ⏳ **NOT yet device-tested.** Scan backoff, reconnect, keepalive, and battery reads are BLE —
  `.unsupported` in the simulator. On a real iPhone with the ring, confirm: (1) reconnect after
  the ring leaves and returns to range, (2) buzz-on-message still instant, (3) battery % shows on
  connect + refreshes on foreground, (4) Test-tab log still reads correctly.
