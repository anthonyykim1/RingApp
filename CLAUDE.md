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
- **"Running your automation" banner:** No suppression exists on iOS (through iOS 26) for message-trigger automations — Apple privacy block (`Notify When Run` toggle hidden, Shortcuts has no Notifications entry). **Focus mode does NOT work either** — tested on-device 2026-05-28 (iOS 26 / iPhone Air): Shortcuts isn't listable in Focus "Silence Notifications From", and an allowlist + Time Sensitive OFF leaves the visual pop-up. The banner is a system-level activity indicator with no on-device off-switch; the only escape is moving message detection off-device (Mac — see `mac-migration-plan.md`). Don't re-test Focus — see `shortcuts.md` § "Suppressing the running-automation banner".

## Build

Open `RingApp.xcodeproj` in Xcode. Requires iOS 17+ target. App group: `group.com.tonykim.RingApp`.

## Commit

iOS-only — no server, no deploy. When you've reached a working state worth recording:

```
./scripts/commit.sh "msg"     # git add + commit + push
```

Working tree edits made on the Mac Studio auto-sync to the Macbook for Xcode builds (see `~/.claude/CLAUDE.md` → OffCloud sync). Commits represent verified-working states — don't commit just to test; build in Xcode against the synced working tree first.

**Xcode structural changes (add file to target, add package, rename target, change build settings) must be done on Mac Studio's Xcode**, not Macbook's. The forward rsync overwrites Macbook-side `project.pbxproj` edits within seconds, producing "Failed to save RingApp.xcodeproj — backing file modified outside Xcode." Macbook is read-only for project structure; fine for build/run/debug.

## iOS Development Protocol — UI verification via MCP stack (2026-05-26)

User-scope MCPs are wired into Claude Code: **XcodeBuildMCP** (build/run/sim/AX), **maestro** (deterministic UI flows), **apple-docs** (live Apple developer docs). The `/ios-bugbash` and `/ios-fix-bugs` skills are global. No per-project setup is needed.

### Required verification workflow

For any change involving SwiftUI layout, navigation, sheets, gestures, forms, list rendering, or visual bugs:

1. **Build and run via XcodeBuildMCP** — prefer `simulator build-and-run` (single step) for sim, or build for a real device when BLE / background location / NotificationService behavior is being tested.
2. **Pick the right runtime for the surface under test** (see "What does not work in the simulator" below — most of Ring's core surface is device-only).
3. **Inspect via the accessibility hierarchy first** (`simulator snapshot-ui`). Screenshots confirm rendering; the AX tree is authoritative for structure.
4. **Write the verification before the fix:**
   - **Maestro flow** at `maestro/bugs/<short-name>.yaml` for app-level flow bugs. `appId: com.tonykim.RingApp`.
   - **XCUITest** when Maestro can't express the interaction.
   - **Snapshot test** (add `swift-snapshot-testing` to the test target via Xcode if/when you need one) for reusable SwiftUI components.
   Run the verification once to confirm it fails — that's the bug receipt.
5. **Fix the bug.** Stay in scope.
6. **Re-run the verification.** Don't declare done until the build succeeds AND the verification passes AND `simulator snapshot-ui` (or a device AX dump) shows the expected state.

### What does not work in the simulator

This is where Ring deviates hardest from a typical iOS app:

- **Bluetooth LE is unavailable in the iOS Simulator** — `CBCentralManager.state` returns `.unsupported`. Every BLE flow (scan, connect, vibration command, HR-monitor disable, keepalive, battery read) must be tested on a real iPhone with the ring nearby. Maestro flows that depend on BLE state will not pass in sim.
- **Background location session** behaves differently in sim vs. device — sim doesn't suspend the same way, so "did we actually stay alive in background" is a device-only question.
- **NotificationService extension** runs against APNs payloads — testable on device with a real push, not via simulator launchctl tricks.
- **Shortcuts / Siri intent invocation** works in sim but the running-automation banner behavior is iOS-version-dependent (see `shortcuts.md` § "Suppressing the running-automation banner" — **do not re-research this**; there is no on-device suppression, Focus mode included).
- **App Group writes** work in sim, but cross-process visibility (main app ↔ NotificationService) is more representative on device.

For UI-only surfaces (button layout, settings screens, view state independent of BLE), the simulator is fine and faster.

### Accessibility identifier convention

All interactive or test-relevant views must have stable accessibility identifiers:

- Convention: `screenName.elementName` or `screenName.row.<id>`.
- Examples: `home.screen`, `home.vibrateButton`, `settings.intervalSlider`, `pairing.scanButton`.
- Add the identifier in the same commit as the view — don't defer to a separate AX-pass session.

### Forbidden patterns

- Declaring a UI task done from code reading alone.
- Saying "this should work" for BLE behavior without exercising it on device.
- Fixing a bug without a reproducing verification landed first.
- Treating a screenshot as authoritative for structure — the AX tree is.
- Modifying files outside the ticket's scope.

### When stuck

Three failed attempts at the same bug → STOP. Revert speculative changes. Document the blocker (what was tried, what failed, hypothesis about real root cause). Propose a different approach next session. Context is poisoned at that point; iterating harder deepens the wrong direction. The "Suppressing the running-automation banner" entry in `shortcuts.md` is the canonical example — it ate hours, then Focus mode was *assumed* to be the fix, then Focus itself was falsified on-device (2026-05-28). The real lesson: a platform dead end stays dead; stop iterating and route around it (here, off-device capture). Don't repeat the pattern in other areas.

### Pairing with `/goal`

For autonomous batch work, wrap in `/goal` with a machine-checkable condition AND a turn cap (requires Claude Code ≥ 2.1.139):

```
/goal All approved P0/P1 bugs in BUG_BASH.md are fixed or marked BLOCKED after 3 distinct failed approaches. Relevant Maestro flows / snapshot tests pass. App builds via XcodeBuildMCP. Do not modify unrelated files. Stop after 25 turns.
```

Avoid `/goal` for any condition that can only be verified on device (BLE handshake, background persistence, push delivery) — the evaluator can't drive a physical phone.

### Summary required after every iOS task

- files changed
- simulator / device tested (which iPhone, iOS version, ring connected y/n)
- screenshots / AX snapshot taken
- verifications run + pass/fail
- remaining risks (one line, or "none")

### Project docs to read before specific changes

- BLE protocol / connect handshake / HR-monitor disable → `context.md`
- Shortcuts / VibrateIntent / running-automation banner → `shortcuts.md`
- Visual / interaction design → `design.md`
- Mac-build migration history → `mac-migration-plan.md`
