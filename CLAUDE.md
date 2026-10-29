# LocalFlow

Personal, fully offline Wispr Flow replacement for macOS (Apple Silicon, macOS 14+): hold a key,
speak English / Korean / mixed, cleaned text is pasted at the cursor. Native Swift + SwiftUI menu bar app.

- **Plan and status:** `PLAN.md` is the source of truth. Each phase in §7 has a dated **Status** line.
- **Past session notes:** `docs/sessions/` — read these first when continuing on a new machine.
- **Benchmarks:** `bench/` (Python scripts; `bench/results.md` holds the scores). Voice clips in
  `bench/clips/` are git-ignored and personal.

## Build

- `scripts/build.sh` (or `scripts/build.sh Release`): runs xcodegen from `project.yml`, builds, signs with
  the Apple Development certificate, installs to `/Applications/LocalFlow.app`, relaunches.
- Edit `project.yml`, never the generated `LocalFlow.xcodeproj/` (git-ignored).
- Same certificate + same install path keeps macOS permissions across rebuilds.

## Key decisions (details in PLAN.md)

- Speech: WhisperKit `large-v3-turbo` 632 MB on the Neural Engine, language-adaptive prompting (§5).
- Cleanup: rules first; LLM (Qwen3-1.7B 4-bit via MLX Swift to start) only when the gate says so;
  LLM preloads on hotkey down and unloads after idle (§3.1, §4.3).
- English words inside Korean sentences stay in English.
- No network except one-time model downloads.

## Working rules

- Ask the user to test in the real app before committing.
- Add a dated Status line to PLAN.md §7 when a phase changes, and a `docs/sessions/` note for
  sessions with significant decisions.
