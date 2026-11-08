# Dami design spec: JD2 "Notebook with keys"

**Status:** approved by the owner 2026-11-07; D6 (themes) added and approved 2026-11-08. Being built on the `design` branch.
**Drafts:** canvas https://claude.ai/artifact/RhjsDeJm6UhfrCK1EFyqht ("Chosen" and "Dami" rows). The canvas is private to the owner.
**Track:** design, separate from the v1.0 plan, done before v1.0 ships (`docs/sessions/2026-11-07-rename-and-design.md`).

The idea in one line: a quiet paper notebook (cream paper, ink, serif headings, a yellow highlighter) with a few raised keys for
the things you press, and one key colour the user picks.

## 1. Rules for building it (Phase 2)

- **Look only.** No changes to `Dami/Core`, `Insertion`, `Transcription` or `Storage`, or to what any control does. Wording stays as
  it is in the app today, except where §2 says otherwise.
- **One theme file.** All colours, fonts, sizes, radii and shadows come from `Dami/UI/Theme/` (§9). No literal colours or font sizes
  in views.
- **System fonts only:** SF Pro, SF Mono, and New York through `.system(design: .serif)`. Nothing downloaded or bundled.
- **Build changes in `project.yml`** (asset catalog for the icon and glyphs), never in the generated `Dami.xcodeproj`.
- **Work on a `design` branch from `v1.0`.** Commit after the owner has seen it in the real app. `swift test --package-path DamiCore`
  must still pass.

## 2. Decisions for the owner

Each of these changes more than paint. The spec assumes the answer in **bold**. Say if not.

| # | Decision | Today | Spec assumes |
|---|---|---|---|
| D1 | Key colour setting | None | **Add it** (asked for by the owner): Settings › General › Appearance › "Key color", 8 options, Orange default. Stored in UserDefaults. The only new control. |
| D2 | Main window navigation | Sidebar (Home, History, Dictionary, Settings) with a status block at its bottom: status text, "On-device · nothing leaves this Mac", shortcut keycaps | **Top bar of key tabs**, as in the drafts. The status text moves to the top bar's right (dot + word, full text on hover). "On-device…" and the shortcut keycaps already appear on Home, so nothing is lost. Same four sections, same order. |
| D3 | Home stats | A "Today" row of four plain stats | **Same four numbers and labels in a small LCD panel.** Labels as today: Words dictated, Time saved vs. typing, Average speed, Day streak. |
| D4 | Menu panel | System menu look, translucent | **Drawn as paper**, no translucency. Same rows. Check on a busy wallpaper. |
| D5 | UI spelling | Not decided anywhere | **US English in the app** ("Key color", like macOS's "Accent color"). |
| D6 | Theme setting (added 2026-11-08) | None | **Add it** (asked for by the owner): Settings › General › Appearance › "Theme", 7 options (§3.5), Cream default. Sets paper, cards, ink and lines; the key color is chosen separately. Stored in UserDefaults. |
| D7 | Light / dark (added 2026-11-08) | Follows the Mac | **Add a Mode setting** (asked for by the owner): Settings › General › Appearance › "Mode": System (default), Light, Dark. Applies to every window, the menu panel and the HUD. |

Corrections made to the drafts while writing this spec (the drafts had drifted from the app; the app's version wins):
- History actions are **Copy, Fix…, Add a word to Dictionary…, This is what I said / Unmark, Delete**. The drafts showed a
  "Paste again" that History doesn't have.
- Home's "Learned from your edits" card keeps today's text and **"Coming in a later update."** The drafts showed a waiting count and
  a Review button, which don't exist there.
- History search placeholder is "Search dictations".

## 3. Colour

### 3.1 Base tokens

Values below are the **Cream** theme. `paper`, `ink`, `ink2`, `rule`, `keyFace` and `keyEdge` come from the theme (§3.5);
`keyDepth` is `keyEdge` in light and `#0E0D0B` in dark; `selected`/`tape` are `ink`, `onSelected`/`onTape` are `paper`;
`slip` is `keyFace` (Cream light keeps `#FBF7EE`); `track` is `rule` (Cream light `#E6DECF`, dark `#10120E`). `danger`, `lcd*`,
`onHighlight` and white on keys are the same on every theme.


| Token | Light | Dark | Used for |
|---|---|---|---|
| `paper` | per theme, see 3.5 (Cream `#F6F1E7`) | per theme (Cream `#1C1A17`) | Window, menu panel and onboarding background |
| `ink` | `#1F1B16` | `#EDE6D8` | Main text, icons, checkbox edges |
| `ink2` | `#685F54` | `#A69D8E` | Secondary text, captions, times, placeholders |
| `rule` | `#DCD2C1` | `#36322C` | Dividers, row lines, window edge |
| `keyFace` | `#FFFDF8` | `#2A2723` | Secondary keys, cards, text fields, keycaps |
| `keyEdge` | `#D6CCBA` | `#3E3934` | Borders of keys, cards and fields |
| `keyDepth` | `#D6CCBA` | `#0E0D0B` | The 2–3 pt "side" under a raised key |
| `selected` / `onSelected` | `#1F1B16` / `#F6F1E7` | `#EDE6D8` / `#1C1A17` | Chosen tab, chosen language, Settings tab |
| `danger` | `#A3321F` | `#E88A72` | Delete, errors, warnings ("Not in the hint", "History isn't being saved") |
| `lcd` / `lcdText` / `lcdLabel` | `#262A24` / `#DDE8B5` / `#9FAE7A` | `#10120E` / same / same | Home stats panel |
| `slip` | `#FBF7EE` | `#2A2723` | HUD background |
| `slipEdge` | ink at 24% | `#EDE6D8` at 18% | HUD border |
| `tape` / `onTape` | `#1F1B16` / `#F6F1E7` | `#EDE6D8` / `#1C1A17` | HUD note above or below the slip |
| `track` | `#E6DECF` | `#10120E` | Progress bar groove |
| `disabled` / `onDisabled` | `#D6CCBA` / `#857C70` | `#3E3934` / `#857C70` | A key that can't be pressed (no depth) |

### 3.2 Key colours (user setting, D1)

| Option | `key` light | `key` dark | `keyDepth` light | `highlight` light | `highlight` dark | `paper` light (not used since D6) |
|---|---|---|---|---|---|---|
| **Orange** (default) | `#CC4410` | `#CC4410` | `#8A2C08` | `#F2D74E` | `#E3C53A` | `#F6F1E7` |
| Ink blue | `#2F5BD3` | `#426AD7` | `#1E3E99` | `#F2D74E` | `#E3C53A` | `#F5F2EA` |
| Forest | `#2F7D55` | `#2F7E56` | `#1F5639` | `#F2D74E` | `#E3C53A` | `#F3F1E8` |
| Teal | `#12808A` | `#12808A` | `#0B575E` | `#FFD966` | `#E8C24A` | `#F4F2EB` |
| Plum | `#7A3E8F` | `#9A52B4` | `#55296A` | `#F6C1D6` | `#E5A3BF` | `#F7F2EE` |
| Graphite | `#2B2B2B` | `#707070` | `#000000` | `#A8E6CF` | `#86D4B4` | `#F3F3F0` |
| Rose | `#B03A5B` | `#C14366` | `#7A2540` | `#FFD3B0` | `#F0B98F` | `#F8F1EE` |
| Ochre | `#8A6100` | `#946800` | `#5C4100` | `#F5E68A` | `#E0CF6C` | `#F6F2E6` |

Since D6 the paper comes from the theme, not the key color. In dark mode `keyDepth` is `#000000` for every option. `onHighlight` is always `#1F1B16`, also in dark mode.
The **app icon and onboarding always use Orange**: the icon is the same for everyone, and onboarding runs before the user picks.

### 3.3 Where colour may go

- **`key` is a fill, never text.** Only with white text on it (primary keys, the toggle's on-track), or as a shape with no text: the
  Ready and recording dot, the progress fill, the current step bar, the practice box border. As text on paper it's below 4.5:1
  for some options.
- **`highlight` sits only behind `onHighlight` text:** the latest Recent line, the selected History row, "Replace with" words, the
  chosen language, the "done" check, menu hover. It is never the only sign of anything: a selected row also shows its actions, hover
  also shows the pencil or the pressed row.
- **Status is never colour alone.** The dot always has its word: READY, LISTENING, WORKING, LOADING, PAUSED, ERROR, SETUP NEEDED.

### 3.4 Contrast (measured with the WCAG 2.1 formula, script in the design session)

Text needs 4.5:1; shapes that carry meaning need 3:1.

| Pair | Light | Dark |
|---|---|---|
| `ink` on `paper` | 15.1–15.4 | 14.0 |
| `ink2` on `paper` | 5.5–5.6 | 6.5 |
| `ink2` on `keyFace` | 6.2 | 5.6 |
| `ink` / `ink2` on `slip` | 15+ / 5.9 | 12.0 / 5.6 |
| `danger` on `paper` / `keyFace` | 6.2 / 6.8 | 6.9 / 5.9 |
| `onSelected` on `selected` | 15.2 | 14.0 |
| `lcdText` / `lcdLabel` on `lcd` | 11.3 / 6.1 | 14.6 / 7.9 |
| White on `key` (all 8) | 4.7 (Teal) – 14.2 (Graphite) | 4.7 (Teal) – 7.2 |
| `onHighlight` on `highlight` (all 8) | 11.0–13.5 | 8.4–10.9 |
| `key` dot vs `paper` / `keyFace` (all 8) | 4.2–12.7 | ≥ 3.0 on both (that's why the dark keys differ) |

Found while measuring: a third grey (`#857C70`) the drafts used for the "Beta: … hasn't been tested" line is only 3.7:1. That line
uses `ink2` instead. `onDisabled` on `disabled` is 2.6:1, which WCAG allows for controls that can't be used.

### 3.5 Themes (D6)

| Theme | Light paper / card / ink / ink2 / rule / edge | Dark paper / card / ink / ink2 / rule / edge |
|---|---|---|
| **Cream** (default) | `#F6F1E7` `#FFFDF8` `#1F1B16` `#685F54` `#DCD2C1` `#D6CCBA` | `#1C1A17` `#2A2723` `#EDE6D8` `#A69D8E` `#36322C` `#3E3934` |
| White | `#FAFAF8` `#FFFFFF` `#1A1A1A` `#5F5F63` `#E3E3E0` `#D9D9D6` | `#161617` `#242426` `#EDEDED` `#A1A1A6` `#323234` `#3A3A3D` |
| Stone | `#ECEBE8` `#F8F7F5` `#1E1E1C` `#5C5B57` `#D4D2CD` `#C9C7C1` | `#19191B` `#252629` `#E6E6E3` `#A0A09B` `#37383B` `#434447` |
| Sepia | `#EFE3CC` `#FAF3E4` `#2B1F12` `#6B5843` `#D9C8A8` `#CDB991` | `#1F1912` `#2C241A` `#EFE2CB` `#B09D80` `#3B3125` `#4A3E2F` |
| Sage | `#EEF1E8` `#FAFBF6` `#1C211B` `#5A6356` `#D3DACB` `#C8D0BF` | `#171B17` `#232823` `#E3E9DF` `#9DA898` `#303730` `#3B433B` |
| Mist | `#EEF1F5` `#FBFCFE` `#1A1F27` `#576070` `#D5DBE4` `#C9D0DB` | `#141820` `#1F2430` `#E4E8EF` `#9AA3B2` `#2C3240` `#39404F` |
| Blush | `#F6EEEC` `#FFFAF9` `#241A19` `#6A5755` `#E2D3D0` `#D8C6C2` | `#1D1717` `#2A2222` `#EEE2E0` `#A99896` `#3A3030` `#473B3A` |

Measured on every theme: `ink`, `ink2` and `danger` on paper and cards at least 5.3:1; all eight key colors at least 3:1 against
paper and cards, light and dark (Stone's dark values were darkened to get there). Onboarding always uses Cream with Orange.

## 4. Type

| Token | Font | Size / weight | Used for |
|---|---|---|---|
| `pageTitle` | New York | 36 / semibold, tracking −0.5 | Home greeting, History, Dictionary, Settings |
| `stepTitle` | New York | 28–32 / semibold | Onboarding titles (32 on Welcome and Done) |
| `sectionTitle` | New York | 18 / semibold | Card titles ("Learned from your edits"), date headers in italic 15 |
| `wordmark` | New York | 19 / bold (window), 16 / semibold (menu) | "Dami" |
| `body` | SF Pro | 14 | Dictation text, page subtitles |
| `callout` | SF Pro | 13 | Rows, settings labels, menu rows |
| `footnote` | SF Pro | 12–12.5 | Explanations under sections |
| `caption` | SF Pro | 11 | App · language · words, HUD text |
| `keyLabel` | SF Mono | 10.5 / bold, tracking 1, UPPERCASE | Every key: tabs, buttons, section labels (RECENT, APPEARANCE) |
| `mono` | SF Mono | 11 | Times, counts, MB, shortcuts in keycaps |
| `lcdValue` / `lcdLabel` | SF Mono | 18 bold / 9, tracking 1 | Home stats |

Use the text styles' Dynamic Type sizes where SwiftUI offers them; these are the default sizes. Uppercase key labels are drawn
uppercase but keep their normal-case text for VoiceOver.

## 5. Space, shape and depth

- **Spacing steps:** 4, 6, 8, 10, 12, 16, 20, 24, 32, 48. Main window pages: 52 left and right, 26–34 top. Onboarding: 48.
  Menu panel: 6 outside, rows 10 × 5. HUD slip: 12 × 0, 8 between items.
- **Radii:** window 12, menu panel 10, card 8, HUD slip 7, key and field 6, small keycap 4, highlighter mark 2–3, step dots 4.
- **Depth (the "key"):** a raised key has a solid `keyDepth` shadow straight below it, no blur: 3 pt for keys, 2 pt for keycaps and
  chips. Pressed or selected: 1 pt shadow and moved down 2 pt. Disabled: no shadow. Fields are sunken: inner shadow 1 pt, black 8%.
- **Floating surfaces:** HUD `0 3 10` black 20%; menu panel `0 12 30` black 22%; LCD inner shadow `0 2 6` black 60%.

## 6. Components

| Component | Look | Notes |
|---|---|---|
| **Primary key** | `key` fill, white `keyLabel`, `keyDepth` 3 pt | One per area at most: Fix…, Add, Always fix, Allow…, Continue, Retry/Paste anyway in the HUD |
| **Secondary key** | `keyFace`, `keyEdge` border, `ink` label, 3 pt depth | Copy, Not this, Back, Ask again |
| **Destructive** | `danger` label, no fill | Delete |
| **Tab keys** | Secondary keys in a row; the chosen one uses `selected` and is pressed | Main sections, Dictionary sections, onboarding languages ("Just English" has a dashed edge) |
| **Keycap** (inline) | `keyFace`, `keyEdge`, 2 pt depth, SF Mono | Shortcut keys in sentences (Right ⌘, ⌘V, Esc), menu shortcuts |
| **Card** | `keyFace`, `keyEdge`, radius 8, rows split by `rule` | Settings groups, Replacements table, suggestion boxes, permission rows |
| **Text field** | `keyFace`, `keyEdge`, sunken, radius 6 | Search, add term, find / replace; focus ring in `key` |
| **Pop-up** | Secondary key look, chevrons, radius 5 | Microphone, Cleanup, indicator position |
| **Toggle** | Track `key` when on, `keyEdge` when off; white knob | Settings |
| **Checkbox** | 1.5 pt `ink` square, `key` fill with white check when on | Pause dictation, Open Dami at login |
| **Highlight mark** | `highlight` behind text, radius 2, 2 pt side padding | See 3.3 |
| **Status dot** | 8 pt; Ready `key`; Listening `key` + 3 pt ring at 30%; Error `danger`; others `ink2` | Always with its word |
| **LCD panel** | `lcd`, inset, `lcdText` values, `lcdLabel` labels | Home stats only |
| **Progress** | `track` groove 8 pt; `key` fill; no percentage known → diagonal stripes in `key`/`keyDepth` | Onboarding model step |
| **Step indicator** | 8 pt dots; current is a 22 pt bar in `key`; done `ink2`; to do `keyEdge` | Onboarding footer |
| **Swatch** | 34 pt circle split key / highlight; 2 pt `ink` ring when chosen; name under it | Appearance picker, a radio group for VoiceOver |
| **Paper slip** | `slip`, `slipEdge`, radius 7, height 28 | HUD |
| **Tape note** | `tape` fill, `onTape` text, radius 4, height 22 | HUD notes |

## 7. Screens

**Main window.** Top bar 60 pt: traffic lights, wordmark, tab keys, then status dot + word at the right (D2). Paper background,
`rule` under the bar. Size limits unchanged (min 860 × 560).

**Home.** Greeting in `pageTitle`, the shortcut sentence with keycaps. LCD stats to the right (D3). Below: RECENT list (mono time,
text, "app · language"), the newest line highlighted, "View all →". Side column: "Learned from your edits" with today's text.

**History.** Title + search field. Day headers in italic serif. Rows: time, text, "app · language · N words". The selected row is
highlighted and shows its actions as keys (§2 corrections), Fix… as the primary key, Delete as destructive text at the far right.
Fix sheet and the "Marked as what you said" state use the same components.

**Dictionary.** Title + subtitle; section tab keys with counts (Vocabulary · N, Replacements · N, Suggestions · N when waiting).
Vocabulary terms as chips with ✕ and "Not in the hint" in `danger`. Replacements in a card table; the "Replace with" word highlighted.
Suggestions as cards with Always fix / Not this, then DECLINED with Ask again. All explanations as today.

**Settings.** Title; section list on the left (General, Shortcut, Language, Models, Privacy, Sync), chosen one in `selected`. Groups as
cards. General gains **APPEARANCE**: Mode (D7, three tab keys), Theme (D6, seven small pages) and Key color (D1, eight swatches),
then: "Theme sets the paper, ink and cards; key color sets the main action, the Ready dot and highlights. Mode System follows
your Mac."

**HUD.** Paper slip, 28 pt, all states and wording as today. Recording: `key` dot, level bars in `ink`, time in `mono`, "Tap to stop"
as plain text in hands-free. Transcribing: three dots, one dark at a time. Sent: ink check on `highlight`, no word. Copied: ink
clipboard + today's reason, ⌘V as a keycap. Message: text + one primary key (RETRY, PASTE ANYWAY). Notes as tape, on the side away
from the screen edge. Must stay click-through and never take focus (unchanged code).

**Menu panel.** 300 pt, paper (D4). Header: wordmark, "On-device · nothing leaves this Mac", status dot + word. Hover is the
highlighter. Language as three tab keys (AUTO, EN, second language code), Cleanup and Microphone as pop-ups, shortcuts as keycaps,
warnings in `danger`. Setup panel and all rows as today.

**Onboarding.** 640 × 480, always Orange. Welcome shows the app icon. Language: the chosen language highlighted in the sentence,
English words in the sample highlighted. Permissions and model in cards; ALLOWED with a highlighted check. Footer step indicator and
keys; Continue disabled looks flat.

**App icon.** The JD2 mark: a quote mark in ink, a highlighter stroke, an orange key, on a cream squircle. Needs a final pass: shapes
instead of any type, a slightly heavier quote mark at 16 pt, and dark/tinted variants for macOS 26.

**Menu bar glyph.** Template image, 18 pt, "Speech key" family: a speech bubble. Loading = dashed outline; Ready = outline with two
lines; Recording = filled with the lines cut out; Transcribing = outline with three dots; Needs you = outline with "!". Replaces
hourglass, waveform, record.circle.fill, ellipsis.circle, exclamationmark.triangle one for one.

## 8. Motion and accessibility

- **Motion:** keep today's timings (HUD spring 0.28 s, fades 0.18 s). Key press: 2 pt down, 0.08 s. With **Reduce Motion**: the HUD
  fades instead of scaling, the thinking dots stop with the middle one dark, level bars still move (they are the input meter).
- **Increase Contrast:** `rule`, `keyEdge` and `slipEdge` become `ink` at 60%; `ink2` becomes `ink`; the highlighter gets a 1 pt
  `ink` underline.
- **VoiceOver:** labels unchanged. Swatches are a radio group named "Key color". Uppercase key labels read in normal case. Status dot
  reads its word.
- **Light and dark** follow the Mac by default; Mode (D7) can fix Dami to Light or Dark.

## 9. Implementation notes

- `Dami/UI/Theme/Theme.swift`: colour tokens as dynamic `NSColor(name:dynamicProvider:)` wrapped in `Color`, so light and dark switch
  with the system; key colour options as an enum; font, spacing, radius and shadow constants.
- `Dami/UI/Theme/KeyStyles.swift`: `ButtonStyle`s for primary, secondary, tab and destructive keys; `Keycap`, `Card`, `HighlightMark`,
  `StatusDot`, `PaperSlip` views. Replaces today's `KeycapRow`, `Card`, `PageHeader` looks in `MainView.swift`.
- `AppSettings.keyColor` (UserDefaults `keyColor`, default `orange`) and `AppSettings.theme` (`theme`, default `cream`). These are
  the only changes outside `Dami/UI`, and they add no behaviour beyond storing the choices.
- Theme colours are a `ShapeStyle` (`ThemeColor`) resolved from the environment (`appTheme`, colour scheme, contrast), set once
  at the window, menu panel and HUD.
- Asset catalog via `project.yml`: `AppIcon`, and the five glyphs as template SVG/PDF images.
- Order: theme file → keys and small components → HUD → menu panel → main window → onboarding → icon and glyphs. Each step is
  something the owner can look at in the real app.
- Not touched: `Dami/Core`, `Dami/Insertion`, `Dami/Transcription`, `Dami/Storage`, `DamiCore`.

## 10. Later, not in this spec

- README header, screenshots and a short GIF, made from mockups with made-up text.
- macOS 26 icon variants (dark, tinted, clear).
- Anything that changes behaviour, such as a link from Home to waiting Suggestions.
