# Mac Studio Migration Plan

Planning doc for moving message capture off the iPhone and onto the Mac Studio, to eliminate the "Running your automation" banner and add WhatsApp/Signal support.

## Goal

Eliminate banner annoyance and broaden notification sources. Ring stays tethered to iPhone for mobility — Mac does capture only, signals the phone, phone vibrates the ring.

## Confirmed facts (research 2026-05-22 / 2026-05-23)

### iPhone Shortcut banner cannot be suppressed in iOS 26.3
Comprehensive web search confirmed: no native suppression for the "When I get a message" trigger in iOS 26.3. Apple's official Communication Triggers page lists only Sender + Message Contains as parameters — no `Notify When Run` toggle, no service-type filter. This is a deliberate Apple privacy restriction applied to all Communication triggers (Message, Email, Wi-Fi, Bluetooth, Arrive/Leave). Consistent from iOS 15.4 through 26.3. Focus mode allow-list remains the only system-level mitigation.

### iPhone "When I get a message" automation fires for iMessage ONLY
User confirmed by testing: SMS does not trigger the existing iPhone Shortcut. Backed by scattered Apple Developer Forum reports. This means the current iPhone Shortcut already provides zero SMS coverage — disabling it loses no functionality we currently have.

### Shortcut cannot filter by message service (iMessage vs SMS) at trigger level
No `Service` / `Type` property exposed. Only Sender + Message Contains. So a "green-only" or "blue-only" filter at trigger time is not possible — but moot given the iMessage-only firing above.

### Race condition: iPhone Shortcut always wins
iPhone Shortcut fires on the direct system message-arrival event. Mac chat.db detection + push back to phone adds 100–1000ms minimum. Therefore the Mac path cannot "arrive first" to suppress the Shortcut — and the Shortcut's `lastBuzzByKey` debounce only prevents double-buzzing, not banner display. **The Shortcut must be disabled entirely for blue messages to suppress its banner.**

### Mac can receive SMS via TMF or Messages-in-iCloud
- **Text Message Forwarding (TMF)** on dual-SIM iPhone forwards SMS/MMS/RCS from **both lines** to Mac in real time. No per-line toggle.
- **Messages in iCloud** also brings SMS/MMS/RCS to Mac via iCloud sync.
- Either path lands messages in `~/Library/Messages/chat.db` on Mac with a `service` field ("iMessage", "SMS", "RCS"), readable by a watcher.
- **TMF preferred over iCloud Messages**: real-time push (not sync), doesn't use iCloud storage, doesn't park work-line SMS in iCloud servers. Smaller exposure surface.

### Signal Desktop + WhatsApp Desktop exist for macOS
- Signal: native Electron app at signal.org/download/macos/. Cleanest programmatic access via `signal-cli` (separate registered device under same number).
- WhatsApp: native Mac app exists. No clean API — local DB exists but is not a stable surface. Weak link.

## Policy implication (user decision made)

User has decided to enable TMF despite work IT preferring it off. The trade-off accepted:
- Work-line SMS (2FA codes, internal alerts, etc.) lands in Mac's Messages.app and stays in `chat.db` history.
- If Mac is backed up via iCloud Backup or Time Machine, work messages persist there too.
- TMF (iPhone → Mac direct) is less exposed than Messages-in-iCloud (iPhone → iCloud servers → Mac).

## Chosen architecture

```
All messages (iMessage + SMS, work + personal lines)
   → arrive on Mac (TMF for SMS, Apple ID for iMessage)
   → Mac chat.db
   → Mac watcher (LaunchAgent / Swift CLI)
   → silent APNs push to RingApp
   → NotificationService extension (NSE) on iPhone
   → BLE buzz to ring

iPhone "When I get a message" Shortcut: DISABLED ENTIRELY.
No banner, ever. 100% coverage. Single capture path.
```

Future additions:
- Signal via `signal-cli` on Mac, same downstream path.
- WhatsApp deferred until/unless a clean capture path emerges.

## Open work

1. **Verify NotificationService extension** is wired up enough to receive silent pushes and trigger BLE writes via shared App Group. Inspect `NotificationService/` directory and current Info.plist / entitlements for push capability + background modes. Confirm what it already does and what's missing.

2. **Spike Mac chat.db watcher** — Swift CLI or simple LaunchAgent that:
   - Watches `~/Library/Messages/chat.db` via FSEvents (with polling fallback).
   - Reads new rows (filter by `ROWID` watermark or `date` column).
   - Extracts: sender, conversation handle, service, body preview.
   - Confirms both iMessage and SMS rows appear once TMF is enabled.

3. **APNs sender on Mac + push receipt in RingApp** — design the silent push payload (just a debounce key + conversation handle is enough), set up the Apple Developer push cert / key, write a tiny Mac sender. iPhone NSE wakes on push, calls into shared container to trigger `VibrateRingIntent` (or equivalent direct path through the app group).

4. **Disable iPhone Shortcut** — once #1–#3 work, turn it off and confirm no regression. Keep the `VibrateRingIntent` code intact in case we ever want to re-enable for fallback.

5. **Signal-cli integration** — add as second event source feeding the same Mac → push → NSE pipeline.

## Key constraints to remember

- **Ring stays on iPhone.** Mac never touches BLE. Mac only signals.
- **No global "notification observer" on macOS** for security reasons — must read per-app data stores (chat.db, signal-cli) directly.
- **Debounce by Sender** key already exists in BLEManager. Re-use for the push payload.
- **iOS Shortcut `Sender` property is the conversation ID** (Name returns body — don't use Name).
- **HR monitoring disable on connect** (`[0x22, 0x11, 0x00]`) must not be removed — see `CLAUDE.md`.

## Sources

- [Communication triggers in Shortcuts on iPhone — Apple Support](https://support.apple.com/guide/shortcuts/communication-triggers-apdd711f9dff/ios)
- [Automations (Shortcuts) do not have Notify when run — Apple Discussions](https://discussions.apple.com/thread/255767636)
- [How to Hide Running Your Automation Notifications — How-To Geek](https://www.howtogeek.com/810648/disable-running-your-automation-notifications-iphone-ipad/)
- [How Can I run an automation on SMS — Apple Developer Forums](https://developer.apple.com/forums/thread/705659)
- [Text forwarding with Dual SIM — Apple Discussions](https://discussions.apple.com/thread/254440866)
- [Get SMS, MMS, and RCS texts from iPhone on Mac — Apple Support](https://support.apple.com/guide/messages/get-sms-mms-and-rcs-texts-from-iphone-icht8a28bb9a/mac)
- [Why use both Text Message Forwarding and Messages in iCloud — Macworld](https://www.macworld.com/article/232870/why-use-both-text-message-forwarding-and-messages-in-icloud.html)
- [Set up iCloud for Messages on all your devices — Apple Support](https://support.apple.com/guide/icloud/set-up-messages-mm0de0d4528d/icloud)
- [imsg CLI for Apple's Messages.app — GitHub](https://github.com/openclaw/imsg)
