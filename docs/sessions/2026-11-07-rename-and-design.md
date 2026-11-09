# 2026-11-07 — Renamed to Dami, design track started

## Rename: LocalFlow → Dami

- **Name:** Dami (담이, from 담다 "to hold, to put in": it holds what you say). Said DAH-mee. Chosen by the owner over Malhae, Sori
  and Iyagi, which were hard to say in English. A quick web check found no dictation app named Dami. **Dictami**, a paid offline Mac
  dictation app that works the same way, exists with a similar ending. Trademark not checked.
- **What changed (commit `1f6b554`, fast-forwarded into `v1.0`):**
  - Folders `Dami/` and `DamiCore/`.
  - Targets `dami-eval` and `dami-guard`.
  - Bundle ID `io.github.giojung97.dami`, also used as the log subsystem.
  - Env var `DAMI_TEAM_ID`; app installs to `/Applications/Dami.app`.
  - Data in `~/Library/Application Support/Dami/` (`Dami.sqlite`, `Dami.backup.sqlite`).
  - All UI text and the current docs.
- **Kept on purpose:**
  - Dated history keeps the old name: `docs/sessions/` before today, `docs/plans/v0*`, `bench/cleanup_results.md`.
  - The repo folder `localflow/` (PLAN.md tree) and the GitHub URL. The GitHub repo is not renamed yet: the owner decides with the
    design release.
  - `~/.cache/localflow-bench` (existing local venv).
- **Migration:** none in code. The owner chose a fresh start.
  - History DB and audio were copied by hand into the new folder.
  - Settings, permissions and the speech model started fresh, like a new install.
  - The owner went through onboarding and tested history, and English and Korean dictation: no problems.
- **Old install removed:**
  - `/Applications/LocalFlow.app`, `~/Library/Application Support/LocalFlow`.
  - Caches, including 1.9 GB of Core ML cache.
  - The `com.localflow.app` defaults and TCC entries.
  - Backup of the old data: `~/Documents/LocalFlow-backup-2026-11-07` (DB, audio, model, settings).
- **Health counters** (UserDefaults) restarted from zero under the new bundle ID. Earlier counts are only in the backup plist.
- **Tests:** `swift test --package-path DamiCore` passes 150/150. One test's token data was "로컬플로우" split into two tokens. It was
  changed to " 다미로", because a one-syllable token falls under the single-letter rule.
- **Not committed:** `docs/plans/v1.0.md` was already untracked. Its text was renamed to Dami too.

## Design track (separate from v1.0, done before it ships)

- Not a v1.0 milestone. Covers the app look, app icon, menu bar glyph and README visuals. README screenshots/GIF come from mockups with
  made-up data.
- **Direction chosen: JD2 "Notebook with keys".**
  - Cream paper, serif headings and a yellow highlighter.
  - Raised keycap tabs and buttons, a small LCD stats panel.
- **Key colour is a user setting:** Settings › General › Appearance, 8 palettes (Orange default, Ink blue, Forest, Teal, Plum, Graphite,
  Rose, Ochre). This is a new setting the owner asked for. Light and dark follow the Mac.
- Drafts canvas (not in the repo): https://claude.ai/artifact/RhjsDeJm6UhfrCK1EFyqht
- **Next:**
  - JD2 HUD states, menu panel, Dictionary and Onboarding screens.
  - Dami icon and menu bar glyph.
  - Then a short spec for approval.
  - Then implementation on a `design` branch: look only, no behaviour change, shared styles in one theme file.
