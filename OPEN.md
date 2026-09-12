# Open — RingApp   (updated 2026-09-12)

Numbers (**#1**…) are stable handles for conversation — they are kept even as items close, so a
gap is normal and a number never gets reused.

## Active
- [2026-09-12] **#1** `project.yml` (an XcodeGen spec, and xcodegen IS installed) and the generated `RingApp.xcodeproj/project.pbxproj` are BOTH tracked in git, and nothing says which is authoritative. It matters because the standing rule "do structural Xcode changes in Xcode on Mac Studio" assumes the `.xcodeproj` is the source — if `project.yml` is, the right move is editing the spec and regenerating. Undetermined, not guessed. Decide before the next structural change (add file to target, add package, change a build setting), then state the answer in `CLAUDE.md`.
- [2026-09-12] **#2** RingApp is NOT harness-covered — no `harness.toml`, so every code change here is ungated and a Codex ticket against it would fail at setup. Needs `harness init /Users/tonykim/OffCloud/RingApp`, its deliberately-failing placeholder gate replaced with one that actually exercises this repo (the build is the obvious candidate), and `harness gates` confirmed red → green. Markdown-only work like this onboarding is unaffected.
- [2026-09-12] **#3** Onboarding readiness is green but the three context goals are still NOT YET SEEN in this repo — they need events that only Tony can trigger. Sequence: he `/clear`s, the first turn of the new session re-runs `context_health.py` (proves goal 1, a clear losing nothing), then he checkpoints (proves goal 3). Goal 2 proves itself on the first automatic consolidation pass — ⛔ do not hand-run `consolidate.py` in this repo before that pass, because a manual run empties the queue and leaves goal 2 unprovable.
## Parked
## Dropped
