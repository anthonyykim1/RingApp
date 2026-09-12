# History — RingApp

Newest first. One dated entry per episode. Verbatim closed ledger items go to `LEDGER_ARCHIVE.md`;
this file carries one compressed line each.

## 2026-09-12 — `project.yml` made authoritative, and the repo onboarded to the harness

Two standing questions closed in one pass (`OPEN.md` #1 and #2), both settled by execution rather than
by reading.

**#1 — `project.yml` is authoritative; the committed `.xcodeproj` is a generated artifact.** The repo
tracked both and nothing said which was the source, which mattered because the global "do structural
Xcode changes in Xcode on Mac Studio" rule assumes the `.xcodeproj` is. Method: `rsync` the working tree
to a scratch copy without `RingApp.xcodeproj`, run `xcodegen generate` there, diff the result against the
committed `project.pbxproj`. **They match, UUIDs included** — so the spec is a complete description of
this project and nothing structural has drifted since it was written.

⭐ **The diff found a live trap that had nothing to do with the authority question: `project.yml` was
missing `DEVELOPMENT_TEAM`.** Every one of the four build configurations in the committed project carries
`DEVELOPMENT_TEAM = 4RXYGKM63F`; the spec named it nowhere. So `xcodegen generate` in this repo produced a
project **that cannot sign for a device** — and the device is the only place this app's core surface can
be tested at all. Fixed by adding it per target (project-level placement was tried first and produces a
different, though equivalent, layout). Re-diffed to confirm: all four `DEVELOPMENT_TEAM` settings then
match exactly. **The residual three deltas are cosmetic and do not change the build** —
`explicitFileType` → `lastKnownFileType` on the two product references, plus an added `TargetAttributes`
block naming the same team. ⚠️ **The committed `.xcodeproj` was deliberately NOT regenerated**, because
only a hardware build can validate that, and `#4` already shows this repo carrying one device-unverified
commit. Decision written into `CLAUDE.md` as an explicit override of the global rule.

**#2 — the repo is harness-covered, with a gate proven red → green → red.** `harness init` scaffolds a
placeholder that fails on purpose; it was replaced with one `ios_build` gate:
`xcodebuild -project RingApp.xcodeproj -scheme RingApp -sdk iphonesimulator -configuration Debug
-derivedDataPath build build CODE_SIGNING_ALLOWED=NO`. Verified in the environment gates actually run in
— a detached worktree at `HEAD` holding only tracked files:

- **`BUILD SUCCEEDED`**, and the worktree stayed clean afterwards on both tracked and untracked files
  (`build/` is already gitignored, so derived data cannot enter a run diff and trip diff-scope).
- **Both targets compile under the one gate** — confirmed not by trusting the declared dependency but by
  listing the built bundle and finding `PlugIns/NotificationService.appex` inside it.
- ⭐ **The gate can actually FAIL.** Garbage appended to `BLEManager.swift` in the throwaway worktree
  produced `BUILD FAILED` with real compile errors. A gate that cannot go red is the specific defect
  `harness init` was changed to stop scaffolding, so this check is not optional.
- Timing: `[FAIL] placeholder` → `[OK] ios_build`, **7.9 s from cold** after deleting derived data. The
  first 7.7 s reading was re-run cold precisely because it looked too fast to be a real build.

**Two traps avoided, both documented in the harness README and both repo-specific:** the gate does **not**
run `xcodegen`, because regeneration here is **not** a no-op (the three cosmetic deltas above would dirty
`project.pbxproj` on every run — the README says test this per repo and never infer it); and the command
uses `-sdk iphonesimulator` rather than `-destination 'generic/platform=iOS Simulator'` **specifically to
contain no apostrophe**, since a gate is `shlex`-split and one quote breaks it before it runs.

`[prompt]` carries the do-not-self-verify sentence (Codex's sandbox cannot reach CoreSimulator and
false-escalates on `supportedRuntimes=[]`) plus the standing BLE warning. `[disclosure]` states plainly
that the gate is compile-only and **BLE-blind**, with per-area notes firing on `RingApp/BLE/**` and
`NotificationService/**`. ⚠️ **`.swift` is a guarded extension, so Swift changes here now require a
ticket** — `.yml` is not guarded, which is why the `project.yml` edit above needed no escape hatch.

⛔ **One correction worth keeping: the closed-ledger marker is the literal token `[status: closed]`, not
a tick and not the word CLOSED.** The global `CLAUDE.md` still describes the older form. Read from
`ledger_common.py` — the token must fall in the first 200 characters and is ignored inside backtick code
spans — and both closures were then verified by calling the machinery's own
`ledger_item_declares_finished()` on the actual bullets rather than by eye.

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
