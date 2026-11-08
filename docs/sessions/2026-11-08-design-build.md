# 2026-11-08 — Design built on `design`, README

Continues `2026-11-07-rename-and-design.md`. Branch `design` from `v1.0`; nothing merged or pushed.

## What was built

Every step was compiled, installed with `scripts/build.sh` after the owner said yes, checked by the owner in the real app, then
committed. `swift test --package-path DamiCore`: 150/150 after each step. Details and commits: `docs/design/spec.md` §11.

- Theme tokens and key components; HUD, menu panel, main window, Settings, onboarding redrawn. Wording, steps and actions unchanged.
- App icon and menu bar glyphs from scripts, checked by rendering them to PNG and looking (two glyphs were wrong at first: an SVG
  with a duplicate attribute didn't load, and a stroke covered the recording glyph's cut-out lines).
- README: icon header, a demo GIF drawn by a script with made-up text, Install first.

## Decisions (owner)

- **D6 Themes:** seven (Cream default, White, Stone, Sepia, Sage, Mist, Blush), separate from the key color. Paper now comes from the
  theme, not the key color. Stone's dark values were darkened so every key color stays at 3:1 on its cards.
- **D7 Mode:** System (default), Light, Dark, for the whole app. Asked for after the themes all looked dark on a Mac in dark mode.
- **Settings tab:** opens on General, keeps the last tab while the main window is open, back to General when it closes. Before, it
  always opened on Shortcut, a leftover from the first commit with no recorded reason.
- History keeps its list-and-detail layout; Copy is no longer the prominent button, Fix… is (spec §7).

## Found along the way

- Dark-mode key colors for Ink blue, Plum, Graphite, Rose and Ochre were too dark against dark paper (2.4–3.0:1); lighter dark
  values were set (spec §3.2). Found by computing contrast instead of estimating it.
- The drafts had drifted from the app (a "Paste again" in History, a "Review" button on Home that does nothing in the app); the app's
  version was kept.

## Open

- **Tutorial after setup** (owner's idea): a few cards on where Dami lives and how to use it. A new screen and behaviour, so not part
  of the design spec. Owner to decide whether it goes in v1.0 (its goal is people trusting it on first install) or after.
- Merge `design` into `v1.0`, and when; rename the GitHub repo and push. Both the owner's call.
- Optional polish of the parts left in the system look (spec §11).
- Not verified: Increase Contrast, Reduce Motion, VoiceOver, other Macs.
