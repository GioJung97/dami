# Known issues

Things we know about and chose not to chase yet. When someone reports one, start here.

## Green check, but the text didn't appear

**What happens:** Dami shows the check, but nothing shows up in the app. The check only means ⌘V was sent. Accessibility
said the focused element could take text, and it couldn't. The speech isn't lost: it's in History and in the menu's Recent list.

**Why it isn't fully solved:** apps describe their focused element in different ways, so `FocusClassifier` (in `DamiCore`)
decides by how an app is built, and outside web pages an unsure answer means paste. That's right for fields that don't describe
themselves, and wrong for a non-field that claims a selection or says nothing.

| Kind of app | Tested | Result |
|---|---|---|
| Native (Notes, Finder) | Yes | Correct |
| Chrome: blank page, address bar, search box, Google Docs | Yes | Correct |
| Terminal (cmux) | Yes | Correct |
| Safari, Electron (Discord, Cursor, VS Code), Word | **No** | Unknown. Electron is the most likely place for this. Non-field areas such as a file list or channel list are the risk |

**How to diagnose a report**
1. Ask which app, and where the focus was (for example "the file list in VS Code").
2. Have them run this in Terminal, reproduce it once, and send the line. It has the app, role and decision, never any text:
   ```
   log stream --level debug --predicate 'subsystem == "io.github.giojung97.dami" AND category == "insertion"'
   ```
3. Add that case to `FocusClassifierTests` first, then fix `FocusClassifier`. Being unsure on a web page means copying, which only
   costs the user one ⌘V, so prefer that over a silent miss.

**Earlier example:** a Chrome page with nothing focused reported `AXWebArea` or `AXGroup` with a selection range. Google Docs
types into a hidden `AXGroup` / `AXEmptyGroup`, so that subrole counts as a field. This is an observation from one log and may
also match non-fields on other sites.

## Bluetooth microphones

AirPods connected, but of 8 wireless starts only about 3 produced a saved dictation in M2 testing. Cause not investigated. It's
on the later list in `docs/plans/v0.2.md`.

## Spacing in fields Accessibility can't read

In terminals such as cmux, spacing is a guess from the previous dictation: same app, within 2 minutes, no key pressed since. A
longer pause can join sentences, and moving the cursor with the mouse alone can add an extra space. If the 2 minutes is too short
in practice, it's `previousDictationWindow` in `InsertionSpacing`.

## Very short dictations

**Fixed (2026-11-05).** Clips of about 1–1.4 s often came back empty and showed "No speech recognized". Numbers-only diagnosis on the
owner's Mac: neither VAD nor the no-speech thresholds caused it. With the language prompt, Whisper ended at once. Retrying without the
prompt and with 0.5 s of silence on each side brought back all 5 empty clips, while silence alone brought back none. The app now does
that retry, only when a result is empty. Owner tested: 8 short phrases in Korean and English, 6 needed the retry, all pasted, about
0.9 s each.

**Still open:**
- **Language detection on very short clips.** A 0.7 s Korean "네" was detected as English and came out as an English word. Detection
  has very little sound to go on.
- **Longer clips dropped as empty.** Before the diagnosis, one 3–10 s and one over-10 s dictation came back empty on 2026-11-05. The
  retry may or may not catch these: the drop counters will show if it keeps happening.

**Since v0.3.1 (2026-11-06):** drops are counted by day in `dropCountsByDay`, with `empty` apart from `hallucination`. The older,
undated `dropCounts` counted empty results as `hallucination`, so its 27 there include both. An empty result of 1 s or more offers
Retry, which forces the other language, the most likely miss on a short clip. A filtered stock phrase offers Paste anyway. Whether
a retry ever brings back real speech is still unseen: `retry.text` will show it. A "네" under 1 s gets no Retry, since shorter
drops are mostly stray presses.

## Made-up text during long pauses

In a 10:39 hands-free recording where the owner spoke a few words, waited and spoke again, text that wasn't said appeared in the
result (2026-11-04). The owner spoke only a few words in that time and considers this expected, not a bug: not investigated, and
to be reopened only if it shows up in real use. The hallucination filter only checks a whole output, so it can't remove a made-up
part inside real speech.

## Long recordings may not capture everything

In a 5:00 hands-free test the owner felt not all of the speech came through (2026-11-04). That test was about the time limit, so
accuracy wasn't checked and nothing was measured. Worth a look when accuracy is measured on longer audio.

## First-run setup: what's fixed and what's still open

Another user tried a build from source on their own Mac (2026-11-04) and reported these. Fixed on branch `setup-fixes`, and the owner
tested a full first run on this Mac (2026-11-05, macOS 15.3). Another Mac hasn't been tried.

**What was wrong**
- **Setup could get stuck on Permissions.** With Input Monitoring asked before Accessibility, its row stayed on "Allow…" until the app
  was reopened, so someone who answered Later in macOS's prompt couldn't continue.
- **macOS's prompts came too early or doubled.** The Accessibility prompt appeared at launch, because creating the event tap triggers it,
  and pressing Allow opened two windows.
- **The full menu was open during setup,** so someone couldn't tell whether setup had finished.
- **"Preparing…" looked frozen,** with the bar sitting at 100%.

**What the owner's tests found about Input Monitoring.** With Accessibility allowed first, the check turned true at once, Dami
didn't appear in Input Monitoring in System Settings, and the shortcut and dictation worked with no reopen. Setup therefore asks for
Microphone and Accessibility, and shows Input Monitoring only if the shortcut hasn't started 5 seconds after those two. That row stays
because other macOS versions may differ, and without it a failure there would be a shortcut that silently does nothing. It can go if
testers on other versions never see it.

**Decided (owner, 2026-11-04):** the menu bar icon stays during setup, since closing the setup window would otherwise leave no way to
reach or quit the app. Until setup is done it opens a small panel with what's left, "Continue setup" and "Quit". The lock depends only
on `hasCompletedOnboarding`, so History stays reachable if a permission is removed later.

**Not verified**
- The Input Monitoring row and its advice, which can't be reproduced on this Mac.
- The in-app "Quit & Reopen" button. It wasn't recorded as pressed.
- Any other Mac or macOS version.
- Whether the Window menu can open the main window during setup, which would get around the lock.
- "This can take a few minutes the first time" on the Prepare step. That time hasn't been measured, and a Mac that has prepared the
  model before may be faster than a real first run.

**Not done:** a download ETA. Nice to have. It shows "X of 632 MB" today. If added, keep it rough ("about 2 min left"), and check first
that the download's progress moves smoothly.

## SwiftUI "Publishing changes from within view updates" (2026-11-05)

The system log showed this runtime warning three times on 2026-11-05, around saving fixes in History during M3 and M4 testing. It
hasn't appeared since, including the M2 and offline tests. The likely place is `HistoryView`'s `openRequestedFix` or a state change
during a view update. Not investigated. It loses nothing seen so far, but it can make a view skip an update.

## Korean Replacements miss some particles and endings (2026-11-06)

From the v0.3.1 review. A Korean rule matches with up to two particles after it, from a fixed list. Some aren't in it: "하고",
"이나", "께서", and copula endings such as "이야", "였어", "라서". So a rule for "클라우드 코드" doesn't change "클라우드 코드였어". This errs
toward changing less, never toward changing meaning, so it waits. If added, check each against words it could cut ("하고" ends
verbs too).

## Language detection encodes the audio a second time (2026-11-06)

Found in v0.4 M1. In Auto, `Transcriber.detectLanguage` runs the audio encoder itself, then transcription runs it again. It costs
about 0.44 s on every Auto dictation, a quarter to a third of the 1.6 s from release to paste. A fixed language skips it. **To fix
before v1.0** (owner, 2026-11-06): reuse the encoder output for transcription. Check afterwards that detection picks the same
language on the bench clips.

## English dictations sometimes come back empty on the first run (2026-11-06)

Found in v0.4 M1. Both English dictations among 11 samples came back empty with the vocabulary prompt and were recovered by the
retry without it, about 0.45 s later. Nothing was lost. Two samples can't say how often this happens or why. Watch it in the latency
samples (`runs=2` with `lang=en`) before doing anything.

## HUD not visible while recording, after a fresh install (2026-11-07)

**What happened:** on the first run of Dami (fresh settings and permissions after the rename), the shortcut and dictation worked
and text was pasted, but the HUD never showed while the keys were held. A window log (owner and window bounds only, no content)
found no HUD window on screen during the recording. After the paste it was on screen for about 0.5 s, with its x position
outside the display and the menu bar item at several x positions at once, as during a screen-wide slide.

**What fixed it:** the owner turned Dami off and on in Accessibility, then quit and reopened Dami. Both were done together, so it
isn't known which one fixed it. That app session had run since the first launch, through setup.

**Not known:** the cause, whether it happens on every fresh install, and whether it is tied to setup, Spaces or cmux. It matters
for v1.0 because a new user who sees no HUD can't tell recording has started. **Check on the next fresh install** (a tester's Mac
or a new user account): does the HUD show during the first recording right after setup, before any reopen?

**Unrelated, seen at the same time:** the menu bar item sometimes disappears when an app with many menus (cmux, Cursor) is in
front. That's macOS hiding status items behind the notch. Dami's item sits just right of it.
