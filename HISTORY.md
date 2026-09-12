# History — RingApp

Newest first. One dated entry per episode. Verbatim closed ledger items go to `LEDGER_ARCHIVE.md`;
this file carries one compressed line each.

## 2026-09-12 — Onboarded to the context system

Onboarded per `~/OffCloud/claude-config/ONBOARD-THIS-REPO.md`. The repo started with no `HISTORY.md`,
no `OPEN.md` and no `LEDGER_ARCHIVE.md`, so the audit's only fault was "No history document resolves";
nothing was migrated, because no file here was a history. `context.md`, `design.md`, `shortcuts.md`,
`battery.md` and `mac-migration-plan.md` all describe what is TRUE NOW (protocol reference, design
intent, a migration plan) rather than what happened, so they stay where they are and keep their own
`CLAUDE.md` pointers. Earlier episodes are recoverable from git log and the "Session N" markers inside
those docs; they were deliberately NOT back-filled here.

**`CLAUDE.md` trimmed 8,692 → 5,460 bytes (−3,232 B, −37.2%; bytes throughout, `wc -c`).** What went:
the repo's copy of the universal iOS protocol — verification workflow, AX identifier convention,
forbidden patterns, the 3-attempt cap, `/goal` pairing, the required task summary, and "Mac Studio is
the source of truth for `.xcodeproj` edits" — all of which is carried by
`~/OffCloud/claude-setup/IOS_AGENT_STACK.md`, which the global rules already require reading before any
iOS work. Those sections would merely have gone STALE if the global protocol changed, which is the
delete test. What stayed, rewritten as explicit deltas that name the file they override: BLE being
unavailable in the simulator and everything that follows from it, the device/ring-connected reporting
requirement, and the Maestro `appId`. Verified mechanically, not by eye: 25 paragraphs ≥80 chars in the
old file, each matched against the new file and the global stack file, all 25 accounted for. The check
surfaced one real gap — that Shortcuts/Siri invocation DOES work in the simulator — which was restored.
A grep of the removed text for "every turn" / "real-time" found nothing stranded.

**Two stale facts corrected while verifying, both by execution rather than reading:**
- `setHeartRateInterval(0)` in the connect handshake is at `BLEManager.swift:735`, not the **653** that
  `CLAUDE.md` had carried. The rule it documents is intact — it still sits directly after
  `stopVibration()` — only the line reference had drifted.
- `maestro/` does not exist in this repo, so the documented flow path was aspirational; `CLAUDE.md` now
  says the first flow creates it.

**Launch floor — before: 74,688 tokens** (`input_tokens + cache_read + cache_creation` of the first
`usage` record in session `a9165369`, 2026-09-12, this repo's only transcript). ⚠️ **The after figure is
NOT quoted from a paired `claude -p` run, because that method failed here and its output was
incoherent:** across four sequential runs the supposed baseline climbed 42,149 → 85,430 → 129,042 →
129,577 (each run warming the next one's cache), and one "with-file" delta came out NEGATIVE, which is
impossible. That matches the `context-onboard` skill's own warning that the `claude -p` baseline is not
reproducible. What can be said honestly: **3,232 bytes left `CLAUDE.md`, ≈ 881 tokens at this machine's
measured 3.67 bytes/token.** ⭐ **The real after-floor is one number away and needs no new method — read
the first `usage` record of the next fresh session in this repo, i.e. the first turn after Tony's
`/clear`.** Recorded so that turn knows to take it.

**Goal verdicts — `context_health.py`, 7-day window, run 2026-09-12 right after onboarding:
0 proven · 3 NOT YET SEEN · 0 failing, exit 0.** NOT YET SEEN is the correct state here and never means
"working"; what matters is that nothing is FAILING, since a FAILING verdict at this moment would be a
set-up fault.
- **Goal 1 · a `/clear` loses nothing — NOT YET SEEN.** Evidence: `health.log` holds 2 events, both
  `session-start source=startup`; no `/clear` in the window, and no scribe run yet (this session had not
  reached a turn end when the check ran). Proves on the first turn after Tony's next `/clear`.
- **Goal 2 · consolidation runs by itself — NOT YET SEEN.** Evidence: no automatic and no manual passes
  recorded, 0 commits beginning `Consolidate `. Legitimate in a repo with nothing yet closed. ⛔ Do NOT
  hand-run `consolidate.py` here before the first automatic pass — a manual run empties the queue and
  leaves this goal unprovable (`OPEN.md` #3).
- **Goal 3 · a checkpoint works — NOT YET SEEN.** Evidence: no audit turn-ends logged; live tree at the
  time was dirty=3, unpushed=0. Proves at the first checkpoint that ends clean and pushed.

**Audit at the end of onboarding:** `state_audit.py` exits 0 — *"No real faults are present … a
checkpoint would run cleanly in this repo"* — with no FAULT and no ADVISORY. The one fault it opened
with, "No history document resolves", is gone: `_history_paths` now returns exactly `['HISTORY.md']` and
`check_history_document` is silent. Every injected brief is inside the cap for its own channel, measured
on both `SessionStart` and `UserPromptSubmit` (largest: `checkpoint-audit-brief` 4,861 B and
`open-ledger-brief` 4,683 B against a 9,000 B guard; `harness-session-check` on the JSON channel at 529
chars / 2 lines against 8,000 chars / 200 lines).

**State artifacts** live in `~/.claude/state/RingApp/`, outside the repo as required. `CURRENT_STATE.md`
was hand-seeded at 2,188 characters against a 5,000 editorial target and a 6,000 hard cap — 11 pointer
lines, 0 wrapped continuation lines, and the writer's own `looks_like_current_state` and
`validate_current_revision` both accept it. ⚠️ **Seeding it caught a shell bug worth naming:** the stamp
was written as `$TS_`, which the shell read as an unset variable called `TS_`, so line 1 published with
its timestamp silently missing. **A hand-rolled check found it; the file looked fine.** Wrap the variable
(`${TS}`) whenever a stamp is followed by an underscore.
