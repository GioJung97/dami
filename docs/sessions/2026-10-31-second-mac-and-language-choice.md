# Session notes — 2026-10-31: second Mac install and language choice

A Claude Code session on a second Mac: installed LocalFlow from source, then made the app's languages
configurable ahead of a possible open-source release.

---

## 1. Second Mac install

- This Mac had no Xcode. Installed Xcode, `brew install xcodegen`, then
  `sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept` (run in Terminal.app;
  `sudo` can't read a password from Claude Code's `!` prompt).
- Created an Apple Development certificate in Xcode → Settings → Accounts → Manage Certificates.
  `security find-identity -v -p codesigning` still reports 0 valid identities, but `scripts/build.sh`
  signs fine (team `LWXW72VFR2`) and `codesign --verify --strict` passes. Watch whether permissions
  survive rebuilds.
- Disk: Xcode (macOS SDK only) ~10–12 GB, plus build output ~1–2 GB and the 632 MB model.
- `bench/clips/` is git-ignored, so the 30 eval clips aren't on this Mac. Copy them before Phase 3.

## 2. Decisions

- **Languages: English + at most one other**, picked in a new onboarding step and Settings → Language.
  English only is allowed. Offered: Korean (verified) and ja, zh, es, fr, de, pt, vi, hi marked
  "experimental" (mixed prompts and practice sentences written by Claude, not benchmarked).
  Defined in `LocalFlow/Transcription/SpokenLanguage.swift`; adding a language is one entry.
- **Detection restricted to the user's languages.** WhisperKit's `detectLangauge` picks from all 99
  languages and only returns the winner, so `Transcriber.detectLanguage` runs the same single decoder
  step itself and compares only the logits of `en` and the chosen language. The decode then runs with
  that language fixed. Not yet re-benchmarked against Phase 0 numbers.
- Translation check (re-run without prompt) and the MIXED history tag only work for languages with
  their own script (ko, ja, zh, hi). Latin-script languages can't be told apart from English by script.
- Menu bar quick switch kept as Auto / EN / second language; hidden for English only.
- Existing installs migrate to English + Korean; fresh installs default to English only.
- Right-click on the menu bar icon now opens the panel too (status bar button's send-action mask).
- **Speech model choice** (lighter / heavier multilingual option) noted for Phase 6, not built.

## 3. Long-term direction (from the user)

Out-of-the-box bilingual accuracy will be modest (e.g. a word spoken in English vs Korean comes out
all-English or all-Korean). The goal is for accuracy to adapt per user over time from their own
dictations and corrections, all on-device. How to do that is still open.

## 4. Next

- Copy `bench/clips/`; decide whether to start Phase 3 with the rules layer before the LLM benchmark.
- `.dmg` / `release.sh` still open (needed for an open-source release).
