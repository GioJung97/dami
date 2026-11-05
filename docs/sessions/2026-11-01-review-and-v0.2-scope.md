# Session notes — 2026-11-01: project review and v0.2 scope

A review of the project before starting Phase 3. No app code changed. Result: Phase 3 is split, and the next
version has a plan at `docs/plans/v0.2.md`.

## Decisions (from the owner)

- **Ship a usable version first and improve across versions.** Unfinished UI is expected at this stage.
- **v0.2:** reliability, clear states, conservative rules, Raw/Light. **No LLM.**
- **v0.3:** edit capture and word suggestions first, then LLM if measurements justify it. Edits can't be recovered later.
- **LLM means a local model on the Mac,** never an API.
- **Pasting into another app after switching mid-processing: not changing.** The owner's reasoning: people dictate to
  write something, so they normally look at the output before leaving. May be revisited if it happens in practice.
- **Recording limit:** 10 minutes, warning at 9. Rejected: 2–3 minutes (people ramble) and 20 minutes (too long).
- **Microphone:** follow the macOS default, manual choice, no popups, one Bluetooth note.
- **Text history:** Forever by default, since text is small and useful for learning later.
- **Saved audio:** off by default. When on, 7 / 30 / 90 days (default 30). Audio had never been saved on this Mac;
  the owner had assumed for a moment that it was.
- **Self-correction rules:** numbers and times only; broader rules risk changing meaning.
- **Dictionary stays,** with copy fixed. Vocabulary reduced English WER from 4.6% to 1.3% in Phase 0. It's also where
  learned words will end up.
- **Eval clips:** still on the other Mac; move them when preparing v0.3.

## The owner's idea for learning from edits

After a paste, users fix some parts. Those edits are training signal. Deletions and substitutions, aligned with what
was said, deserve weight. Added words are noise, because LocalFlow isn't autocomplete. See `docs/plans/v0.2.md` §7 for
how it is planned, including the point that word timing and confidence reduce the need for saved audio.

## Findings worth keeping

- App latency was 1.29 s average (9 dictations, Debug build) vs. 0.74 s in the benchmark. Remeasure in Release.
- `bench/score.py` ignores spaces, so the Korean spacing problem used to justify the LLM has never been measured.
- §3.1's "skip loading when the gate would skip" can't work as written: there is no transcript at key-down.
- Other apps (2026-11-01): Wispr Flow has auto-detect with a ranked list, an optional switch prompt, and a Bluetooth
  warning, plus a 20-minute limit on Mac. Superwhisper follows the system default with manual choice, no hard recording
  limit, and no automatic history deletion, with users complaining about disk use. VoiceInk has separate text and audio
  retention. Handy limits by count or age. None of those checked uses a size-based limit.
