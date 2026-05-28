# RingApp — Shortcuts Automation Reference

How the iOS Shortcuts automations that drive the RingApp App Intent are set up, and the workarounds needed to make them behave sensibly.

## Why Shortcuts at all

iOS has no API for third-party apps to observe other apps' notifications. The AIZO Ring firmware only auto-vibrates for phone calls (via ANCS). To vibrate for iMessage/SMS/Mail/etc., the only viable path is:

`iOS Shortcuts Personal Automation → "Vibrate Ring" App Intent (exposed by RingApp) → BLE command to ring`

The App Intent is `VibrateRingIntent` in `RingApp/VibrateIntent.swift`. It runs without bringing the app to foreground (`openAppWhenRun = false`). If the ring is disconnected when the intent fires, it calls `startScan()` and polls for up to 3 seconds before giving up.

## Known Shortcuts limitations

- **Per-conversation "Hide Alerts" is ignored.** If you mute a conversation in Messages, Shortcuts automations still fire for it.
- **"Message Contains" cannot be blank** in the "When I get a message" trigger. Workaround: enter a single space.
- **"Running your automation" banner cannot be suppressed — at all.** Confirmed 2026-05-28 on iOS 26 (iPhone Air): no native suppression AND Focus mode does not work (neither blocklist nor allowlist). See [Suppressing the running-automation banner](#suppressing-the-running-automation-banner) below — the only escape is moving message detection off-device (Mac).
- **No SIM-line filter** in the message trigger.
- **The message object is semi-opaque.** In an `If`, the raw Shortcut Input only offers "has any value" / "does not". You have to tap the variable chip and pick a sub-property (Message / Content / Recipients / Sender / Name) to get real comparisons.

## Suppressing the running-automation banner

**Status (researched 2026-05-10; Focus workaround FALSIFIED on-device 2026-05-28, iOS 26 / iPhone Air): no suppression exists for "When I get a message" automations — not even Focus mode.** Stop suggesting the in-automation toggle, the Settings → Notifications path, OR Focus mode — all three are dead ends for this trigger. The banner is a system-level activity indicator (Shortcuts isn't even listable in Focus's "Silence Notifications From"), so nothing on the phone gates it. The only way to avoid it is to not run an on-phone Shortcut for the source at all — i.e. move detection off-device to the Mac Studio.

### Why the obvious paths don't work

1. **In-automation `Notify When Run` toggle (iOS 15.4+):** Apple deliberately hides this toggle for Communication triggers — "When I get a message," email, location, Bluetooth, Wi-Fi. Privacy-mandated: an automation that reads your messages must surface a visible indicator. The toggle is not greyed-out; it simply does not appear in the editor for these triggers.
2. **Settings → Notifications → Shortcuts:** Shortcuts has **no entry** in this list on iOS 17/18. The running-automation banner is a system-level activity indicator (similar to Live Activities / SiriKit progress banners), not a `UNNotification`, so per-app notification toggles cannot suppress it.
3. **Screen Time App Limits (0 min on Shortcuts):** Unreliable; can block the automation entirely. Don't bother.
4. **Wrapping the automation in a "Run Shortcut" call:** The outer trigger still fires the banner. No help.

### Focus mode — TESTED AND DOES NOT WORK (2026-05-28, iOS 26 / iPhone Air)

The theory below (custom Focus silencing everything except an allow-list) was tested on-device and **failed**. Two attempts:
- **Blocklist ("Silence Notifications From"):** Shortcuts is **not listable** in the app picker — there is no app to mute, because the banner isn't a per-app `UNNotification`.
- **Allowlist ("Allow Notifications From" + Time Sensitive OFF):** the visual "Running your automation" pop-up **still appears**.

Conclusion: the banner is a true system-level activity indicator that no Focus configuration gates. Steps retained below only as a record of what was tried.

~~Create a custom Focus that silences everything except the apps/people you explicitly allow.~~ (Does not gate the banner.)

1. Settings → Focus → **+** → **Custom**, name it (e.g., "Ring Silent").
2. **People** → "Allow Notifications From" → add anyone you want to hear from.
3. **Apps** → "Allow Notifications From" → add only the apps that should break through (Messages, Phone, Calendar, etc.). **Do not add Shortcuts.**
4. Toggle **Time Sensitive Notifications: OFF** — otherwise Shortcuts can still break through.
5. **Set a Schedule** → 24/7 or Smart Activation, so the Focus is always active.

Side effects:
- Focus icon (crescent moon or your custom symbol) is visible in status bar / on the lock screen whenever active.
- Apps not on the allow-list are silenced globally — budget time to walk through home screen and add the ones that matter.
- Time Sensitive off can suppress 2FA prompts, ride apps, etc. unless individually allowed.

This needs to be integrated with the user's other Focus modes — they may already have a custom Focus and just need to add Shortcuts to its blocked list (or remove it from the allow-list). Don't propose this as a one-off; ask how it should slot into existing Focus arrangement.

## Messages automation — current setup (Session 3, 2026-04-16)

Single automation that handles ALL text messages with family group chat suppression.

Shortcuts app → Automation → New → "When I get a message"

- **Sender:** (none — fires for anyone)
- **Message Contains:** single space (workaround for non-blank requirement).
- **Run Immediately:** on (otherwise requires manual confirmation each time).
- **Receive messages as input:** on (required so the downstream actions can see the message metadata).

### Flow

```
Receive messages as input
  ↓
Split Text [Shortcut Input → Recipients] by New Lines
  ↓
Count Items in Split Text
  ↓
If Count is greater than 1          ← group chat
  │
  │  Text: "[Sender] [Recipients]"  ← combine into one string
  │    ↓
  │  If Text contains "<wife's phone number>"
  │      (do nothing — family group, suppress)
  │    Otherwise
  │      Vibrate Ring (debounceKey=Sender, debounceSeconds=180)
  │
Otherwise                            ← 1:1 chat
  │
  Vibrate Ring (debounceKey=Sender, debounceSeconds=180)
```

### Why check both Sender and Recipients for wife's number

Recipients lists everyone in the chat EXCEPT you. If wife sends the message, she's the Sender and NOT in Recipients. If someone else in the family group sends, wife IS in Recipients. By combining Sender + Recipients into one Text block, a single "contains" check catches both cases.

### Behavior

| Source | Buzzes? | Why |
|--------|---------|-----|
| 1:1 from anyone | Yes (debounced 3 min) | Falls into Otherwise branch |
| Family group chat (wife is member) | No | Wife's number found in Sender+Recipients |
| Non-family group chat | Yes (debounced 3 min) | Wife's number not found |
| Phone call | Yes (automatic) | ANCS firmware, no Shortcuts needed |

### Debounce

- **Key:** `Shortcut Input → Sender` (phone number of the person who sent)
- **Window:** 180 seconds (3 minutes)
- First text from a person buzzes, subsequent texts within 3 min are silent
- Different people have independent debounce windows
- Resets on app restart (first text always buzzes — desired behavior)

**Important (confirmed 2026-04-16):** Do NOT use `Name` as debounce key — it returns the message body text, not the conversation title. Each message has unique body text so debounce would never match.

## Blocking specific senders (added 2026-04-21)

To suppress buzzes from a named list of phone numbers (any conversation — 1:1 or group), use a **Match Text** regex block instead of multiple `If` actions. The Shortcuts `If` action only supports ONE condition at a time — there is no "Any are true" / "All are true" toggle in the current iOS UI.

### Flow (extends the current messages automation)

Insert right after `Receive messages as input`, before the existing Count/branch logic:

```
Text: "[Sender] [Recipients]"          ← combine into one string (catches 1:1 and group)
  ↓
Match Text
  Pattern: 4155551234|2125551234|3105554321    ← pipe-separated blocklist
  Input:   [combined Text above]
  ↓
If [Matches] has any value
    (empty — blocked, do nothing)
  Otherwise
    ...existing Count/group-chat/Vibrate flow...
```

### Pattern rules

- **Digits only, 10 digits per number** (US). No `+1`, no parens, no dashes, no spaces.
- `|` = OR. Don't put spaces around it — `415555 | 212555` would look for literal spaces.
- Match is **substring**, not exact. `5551234` would match any number ending in those 7 digits (collision risk). 10 digits is the sweet spot: specific enough to be unique, loose enough to match regardless of iOS formatting (`+1...`, `(415)...`, dashes all work).
- To add/remove blocked senders later, just edit the pattern string.
- For iMessage-over-email senders, append the email (escape the dot): `4155551234|jane@example\.com`.

### Why Match Text instead of nested Ifs

Historically Shortcuts' `If` only supports a single condition. Nested `If` / `Else If` chains work but get unwieldy with more than 2–3 blocked numbers. Match Text handles arbitrary list size in one action.

## Previous automation patterns (archived)

### Suppressing group chats (universal — all groups)

Simpler pattern if you want to suppress ALL group chats, not just family:

```
Receive messages as input
  ↓
Split Text [Shortcut Input → Recipients] by New Lines
  ↓
Count Items in Split Text
  ↓
If Count is greater than 1
    (empty — skip)
  Otherwise
    Vibrate Ring
```

**Important:** `Count Recipients in Shortcut Input` does NOT work — it returns 1 regardless, because iOS treats Recipients as a single object. You must split it into lines first.

Note: Recipients returns phone numbers of other participants (does NOT include you). A 1:1 = 1 number = count 1. A 3-person group = 2 numbers = count 2.

### Suppressing a named list of group chats (OR pattern)

Use when you want to silence several specific groups but keep other groups buzzing. Set the `If` action to `Any are true` (logical OR) and add one row per group:

```
If Any are true:
    Name contains "Kimfinity"
    Name contains "Final Three"
    (empty — skip)
  Otherwise
    Vibrate Ring
```

**Caveat:** `Name` may not reliably return the group chat title in all iOS versions. Test with a Show Notification action first.

## Per-conversation debounce (leading edge)

The `Vibrate Ring` App Intent takes two optional parameters:

- **Debounce Key** (string) — an identifier that groups successive invocations together. Different keys have independent debounce windows.
- **Debounce Seconds** (int, default 0) — minimum gap between buzzes for a given key. `0` disables debouncing.

When the intent fires, the app checks the last-buzz timestamp stored for that key:

- More than `Debounce Seconds` ago (or no prior buzz) → buzz and record the new timestamp.
- Within the window → skip silently and log `debounce skip key=<key>`.

Use `Shortcut Input → Sender` to debounce per person. This returns the sender's phone number, which is consistent across messages.

Only the leading edge is implemented — first text in a burst buzzes, subsequent texts within the window are silent. There is no trailing buzz after the quiet period ends; iOS app suspension makes that unreliable in practice (see context.md).

Debounce state lives in memory only — it resets whenever `BLEManager` is recreated (app killed, device restarted, etc.). That's fine in practice: the first text after a restart buzzes, which is the desired behavior.

## Shortcut Input sub-properties (Message type)

Exposed under the variable picker when Shortcut Input type is Message:

- **Message** — the whole opaque object.
- **Content** — the message body text.
- **Recipients** — list of other participants' phone numbers, one per line (does NOT include you). `Count` on this returns 1 (treats it as one object); must Split Text by New Lines first, then Count Items.
- **Sender** — the person who sent the message.
- **Name** — returns the **message body text** (same as Content), NOT the conversation title. Not useful for identifying conversations.

## Testing checklist

After editing any Messages automation:

1. Send a 1:1 iMessage from the configured sender → ring should buzz.
2. Send a message in a group chat that includes the sender → ring should stay silent (if universal suppression is in place) or buzz (if not).
3. Watch for the "Running your automation" banner — its presence confirms the automation fired, even if the ring didn't buzz.
4. If nothing happens at all, check: (a) automation is toggled on, (b) "Message Contains" field is not empty, (c) Test tab in RingApp shows "Connected", (d) manual Start Vibration button in Test tab works.

## Other automations worth considering

Per `context.md`, these are viable via Shortcuts:

- **Mail (personal account)** — "When I get an email" trigger.
- **Alarm stopped / snoozed** — alarm-state triggers.
- **Focus mode changes** — to arm/disarm different vibration behaviors.

Not viable from Shortcuts:

- **Outlook** — blocked by Intune MDM.
- **WhatsApp / Slack / Teams / etc.** — no per-app notification trigger exposed.
