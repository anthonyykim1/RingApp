# Open — RingApp   (updated 2026-10-29)

Numbers (**#1**…) are stable handles for conversation — they are kept even as items close, so a
gap is normal and a number never gets reused.

## Active
- [2026-09-12] **#4** Session-4 battery optimizations (bounded scan backoff, no periodic battery poll, alarm timer gated) were committed to `main` as `bbd9ae3` on 2026-06-05 and have NEVER been device-tested — 127 changed lines in `BLEManager.swift` plus `NotificationService.swift`, `AlarmStore.swift`, `RingAppApp.swift`. BLE is `.unsupported` in the simulator so only hardware can settle it. Also a standing violation of this repo's own rule that a commit here means a state verified on hardware. Needs, on a real iPhone with the ring: (1) reconnect after the ring leaves and returns to range, (2) buzz-on-message still instant, (3) battery % on connect and refreshed on foreground, (4) Test-tab log reads correctly. Checklist: `battery.md` § Verification status.
## Parked
## Dropped
