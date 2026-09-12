# Open — RingApp   (updated 2026-09-12)

Numbers (**#1**…) are stable handles for conversation — they are kept even as items close, so a
gap is normal and a number never gets reused.

## Active
- [2026-09-12] **#3** Context goals, re-measured 2026-09-12 after Tony's `/clear`: **goal 3 (checkpoint) is PROVEN** (2 clean-and-pushed turn ends); goal 1 is one substantive turn away — a scribe DID run post-clear (10:45:35, state written) but the check also requires `map=published|reconciled` and that run reported `nothing-eligible`, which is ordinary for a read-only turn (9 of 37 such runs in `circle`). ⛔ **Goal 2 CANNOT self-prove here — verified by reading `state_audit.py:603-606`: all three launch caps need something that does not exist.** Queue is literally `{"entries": {}}`, no `LEDGER_ARCHIVE.md` exists so archive growth is 0, and the 12-hour cap is skipped entirely when `last is None` (there has never been a pass). It unblocks the moment ONE ledger item closes: a `finished` entry enters the queue, and the pass fires 30 min later. Closing **#1** is the cheapest way. The standing "do not hand-run `consolidate.py`" still holds.
- [2026-09-12] **#4** Session-4 battery optimizations (bounded scan backoff, no periodic battery poll, alarm timer gated) were committed to `main` as `bbd9ae3` on 2026-06-05 and have NEVER been device-tested — 127 changed lines in `BLEManager.swift` plus `NotificationService.swift`, `AlarmStore.swift`, `RingAppApp.swift`. BLE is `.unsupported` in the simulator so only hardware can settle it. Also a standing violation of this repo's own rule that a commit here means a state verified on hardware. Needs, on a real iPhone with the ring: (1) reconnect after the ring leaves and returns to range, (2) buzz-on-message still instant, (3) battery % on connect and refreshed on foreground, (4) Test-tab log reads correctly. Checklist: `battery.md` § Verification status.
## Parked
## Dropped
