# LocalFlow

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
  `/Applications/LocalFlow.app`, relaunches.
- Version: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
- Test: `swift test --package-path LocalFlowCore`. Pure logic goes in that package, with tests.
- Cleanup eval: `swift run --package-path LocalFlowCore localflow-eval` from the repo root writes `bench/cleanup_results.md`.
- Edit `project.yml`, never the generated `LocalFlow.xcodeproj/` (git-ignored).
- Same certificate + same install path keeps macOS permissions across rebuilds.

## Key decisions (details in PLAN.md)

- Speech: WhisperKit `large-v3-turbo` 632 MB on the Neural Engine, language-adaptive prompting (§5).
- Cleanup: conservative rules only in v0.2 (Raw and Light modes). A local LLM as an optional Smart mode is planned for v0.4
  (`docs/plans/v0.4.md`).
- Direction: `PLAN.md` Roadmap is the frame. Build to v1.0 first and improve after it. Check new work against the frame, and put
  improvements after v1.0 unless they lose speech, paste wrongly or break trust.
- English words inside Korean sentences stay in English.
- No network except one-time model downloads.

## Current state and branches

- **v0.2 is implemented but not finished.** The work is on branch `v0.2`. `main` is still the version before it, on purpose.
- **Don't merge `v0.2` into `main`, and don't suggest it as the next step,** until all of this is true:
  1. Every "Must still be tested" item in `docs/plans/v0.2.md` §6 is checked off.
  2. The owner has used it daily for a week without losing speech silently.
  3. The owner says to merge.
- Then: tick §6, add a dated Status line to `PLAN.md` §7, and merge.
- Keep working on `v0.2`. On a new machine: `git fetch && git switch v0.2`.
- Ask before any push or merge. Nothing gets published without the owner's say. The repo is private, and `docs/` and `bench/`
  hold personal notes to review before it goes public.

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
- Never print or change the real database (`~/Library/Application Support/LocalFlow/LocalFlow.sqlite`). Read numbers only, opened
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
