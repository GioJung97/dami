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
- Cleanup: conservative rules only in v0.2 (Raw and Light modes). An LLM (Qwen3-1.7B 4-bit via MLX Swift to start) is
  for v0.3, if measurements justify it.
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

- Ask the user to test in the real app before committing.
- Add a dated Status line to PLAN.md §7 when a phase changes, and a `docs/sessions/` note for
  sessions with significant decisions.
