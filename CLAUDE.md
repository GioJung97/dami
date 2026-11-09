# Dami

Personal, fully offline Wispr Flow replacement for macOS (Apple Silicon, macOS 14+): hold a key,
speak English plus one other language (Korean is the tested one) or both mixed, cleaned text is pasted at the cursor. Native Swift + SwiftUI menu bar app.

- **Plan and status:** `PLAN.md` is the source of truth. Each phase in §7 has a dated **Status** line. A version's plan
  lives in `docs/plans/` (`docs/plans/v0.2.md`) and takes priority over `PLAN.md` where they differ.
- **Past session notes:** `docs/sessions/` — read these first when continuing on a new machine.
- **Benchmarks:** `bench/` (Python scripts; `bench/results.md` holds the scores). Voice clips in
  `bench/clips/` are git-ignored and personal.

## Build

- `scripts/build.sh` (Release by default; `scripts/build.sh Debug` for debugging): runs xcodegen from
  `project.yml`, builds, signs with the Apple Development certificate, installs to
  `/Applications/Dami.app`, relaunches.
- `scripts/release.sh`: the same signed Release build in `build/release/Dami-<version>.dmg`, without installing anything. Not
  notarized; the README explains Open Anyway.
- Version: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`. Raise them when a version merges into `main` (v0.3
  was missed, so it jumped from 0.2.0 to 0.3.1).
- Test: `swift test --package-path DamiCore`. Pure logic goes in that package, with tests.
- Cleanup eval: `swift run --package-path DamiCore dami-eval` from the repo root writes `bench/cleanup_results.md`.
- Edit `project.yml`, never the generated `Dami.xcodeproj/` (git-ignored).
- Same certificate + same install path keeps macOS permissions across rebuilds.

## Key decisions (details in PLAN.md)

- Speech: WhisperKit `large-v3-turbo` 632 MB on the Neural Engine, language-adaptive prompting (§5).
- Cleanup: conservative rules only (Raw and Light modes). A local LLM (Smart mode) was tried in v0.4 and failed its pass line, so
  v1.0 goes without one (owner, 2026-11-06). It may be tried again after v1.0 (`docs/plans/v0.4.md` §7).
- Direction: `PLAN.md` Roadmap is the frame. Build to v1.0 first and improve after it. Check new work against the frame, and put
  improvements after v1.0 unless they lose speech, paste wrongly or break trust.
- English words inside Korean sentences stay in English.
- No network except one-time model downloads.

## Current state and branches

- **Renamed from LocalFlow to Dami** (owner, 2026-11-07, branch `rename`): bundle ID `io.github.giojung97.dami`, data in
  `~/Library/Application Support/Dami/`. Dated history (`docs/sessions/`, `docs/plans/v0*`, `bench/cleanup_results.md`) keeps the
  old name on purpose. The old app, data folder, caches, defaults and permission entries were removed on the owner's say
  (2026-11-07); a backup is in `~/Documents/LocalFlow-backup-2026-11-07`. The GitHub repo and the local folder were renamed to `dami` (owner, 2026-11-08). An older clone may still sit in a `localflow` folder.
- **Design (JD2 "Notebook with keys") is built and merged into `v1.0`** (owner, 2026-11-08). Spec:
  `docs/design/spec.md`. All colours, fonts and sizes come from `Dami/UI/Theme/`; no literal values in views. Theme, key color and
  light/dark are user settings. App icon: `scripts/make-icon.swift`; README GIF: `scripts/make-readme-demo.swift` (made-up text).
- **v1.0 is released as 1.0.0** (owner, 2026-11-08): merged to `main`, tag `v1.0.0`, GitHub Release with the `.dmg`. Before it:
  v0.4 and v0.3.1 (2026-11-06), v0.3 (2026-11-05), v0.2 (2026-11-04). Merged version branches were deleted (owner, 2026-11-08);
  each version is a merge commit on `main`. The next version starts on a new branch from `main`. On a new machine: `git fetch`, then
  `main` or the newest version branch if one exists.
- **Stability is checked continuously, not over a fixed period** (owner, 2026-11-04). Rare problems may not appear in any given week,
  so this runs alongside new work. The owner reports what they notice. **At the end of each milestone, an agent checks what the owner
  can't see:** `scripts/health-check.sh` (failure and drop counters, app errors, crash reports, database health), then reports anything
  unexplained. It prints no dictated text or key identity. Unified logs here only reach back about a day, so the counters are the record
  that lasts. A sent ⌘V still can't confirm text arrived.
- A bug that loses speech, pastes wrongly or breaks trust stops other work until it's fixed.
- **Don't merge a version into `main`, and don't suggest it as the next step,** until both are true:
  1. Every done condition in that version's plan is checked, or recorded as waived and unverified.
  2. The owner says to merge.
- Then: tick the plan's list, add a dated Status line to `PLAN.md` §7, and merge.
- Ask before any push or merge. The repo is public (open source), so a push publishes. Notes, plans and benchmarks are fine to
  publish (owner, 2026-11-05). Never commit credentials: certificates, keys, tokens, passwords.

## Working rules

Common sense that a new session wouldn't otherwise know. Most of these come from real mistakes.

**Git**
- `main` holds what's been verified. Work on a branch. Merging is the owner's call, and it's how something gets marked as done.
- Commit only after the owner has tested in the real app and approved. A passing `swift test` isn't approval.
- Don't suggest merging, publishing or releasing just because code is finished. Check the conditions in this file first.

**Reporting**
- Say what was actually run, and how. "Should work" and "tested" are different. Anything that can't be run here, such as hardware,
  is "needs owner test". Anything skipped is recorded as unverified, never as passed.
- A green result can mean less than it looks. The HUD's check means ⌘V was sent, not that text arrived. Before trusting a signal,
  know what it really measures.
- Numbers from small or synthetic samples are references, not targets. Say what they can't tell us.

**Decisions**
- Ask on product, UX and scope decisions, and when the plan and the code disagree. Decide routine code details yourself.
- Don't widen the scope. Unfinished UI at this stage isn't a defect. Things found along the way go in `docs/known-issues.md` or the
  later list.
- Keep the bar high only for what loses speech, pastes wrongly or breaks trust. Removing less is better than changing meaning.

**The owner's data**
- Never print or change the real database (`~/Library/Application Support/Dami/Dami.sqlite`). Read numbers only, opened
  read-only. Use a scratch folder for tests, since `Store` takes a directory.
- `scripts/build.sh` installs and launches the app, so a new migration runs on the real database right away. Check it on a copy
  **before** building.
- Look at anything before moving or deleting it, and restore what you moved, even when a script fails.
- Logs and notes never contain dictated text or which key was pressed.

**Testing with the owner**
- Keep test lists short and about everyday use, with rare cases under "if you can". Say exactly what to do, with sentences to read.
- Don't ask for something that cuts the owner off from this conversation. With Wi-Fi off they can't reply, so script it to run on
  its own, or have them report afterwards.
- Temporary debug code gets removed before committing. Check with a search.
- Add a dated Status line to PLAN.md §7 when a phase changes, and a `docs/sessions/` note for sessions with significant decisions.
