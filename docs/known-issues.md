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

**Cause found (2026-11-08, v1.0 M1).** AirPods sit in their music mode and switch to their call mode (24 kHz) when the
microphone opens, which took 1.0–2.3 s here. Until then the engine reads the old 48 kHz format, so starting either fails with
`-10868` (format not supported) or succeeds with no audio at all, which ended as "nothing heard": speech lost without an error.
Separately, choosing the built-in mic while AirPods were the default failed the same way, since the engine kept the default
device's format.

**Fixed:** the recorder gives the engine the chosen mic's own format, and starts again on a new engine until audio arrives (up to
4 s), then fails with a plain message. The start sound plays only once audio arrives, 0.3 s later on Bluetooth so the headset's
switch doesn't swallow it, and "Starting microphone…" shows if that takes over 0.5 s. Music in the AirPods still drops to call
quality while dictating, as with any app using their mic; choosing the built-in mic avoids that. Not verified: other Bluetooth
headsets, and the iPhone as a microphone.

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

**Found 2026-11-07 (owner's setup retest), for v1.0:** after Allow in macOS's Microphone prompt, focus goes back to the app that
was in front before, and the owner had to switch back to Dami. The setup window stays open behind. Likely fix: bring the setup
window forward once the microphone request returns. Accessibility needed no reopen, as expected. **Fixed in v1.0 M1:** Dami comes
to the front when the request returns. The owner's install on the second Mac (M5) was reported as working as a whole, not this item
on its own.

**Found 2026-11-08 (owner, first install from the .dmg):** Dami wasn't in System Settings' Accessibility list after Allow, and the
owner added it by hand. Not reproduced the same day: with Accessibility reset (`tccutil reset`) and setup run again on the
`build.sh` install, Allow added Dami to the list and only the toggle was needed. A guess, not checked: the first open from the .dmg
ran from a moved copy (App Translocation, which macOS uses for quarantined apps), so the list entry belonged to another path. Retest on
the next first install from a .dmg: open Dami from Applications after dragging, never from the .dmg window. Not reported again on
the second Mac (M5, 2026-11-08), first install and the update over it. Still unexplained. The README's install steps say to open
Dami from Applications.

**Not verified**
- The Input Monitoring row and its advice, which can't be reproduced on this Mac.
- The in-app "Quit & Reopen" button. It wasn't recorded as pressed.
- Other Macs than the owner's two (macOS 15.3 and 27.0.1), and other macOS versions.
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


**Fixed in v1.0 M2 (2026-11-08).** `ReusingAudioEncoder` wraps WhisperKit's encoder and returns the last output when the mel features
are byte for byte the same, so the first window and a run without the prompt reuse detection's encoding. Detection itself is
unchanged. First samples: transcription about 0.52 s against about 0.8 s before, total 1.25 s against 1.5 s; the latency log shows
`reused=1`.

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

**Retest, same day:** settings and permissions reset (model kept), setup run again, then a recording right after setup with no
reopen: the HUD showed. So it didn't come back on a second fresh setup. A first install that also downloaded the model, on the
second Mac (v1.0 M5, 2026-11-08), was reported as working as a whole. Still unknown: the cause, and other people's Macs.

**Seen again (owner, 2026-11-12), and narrowed down.** With Dami running for 4 days, the HUD showed only on desktop 6 of 8. It
works on every other desktop too, but there it stays on desktop 6, so it shows while you swipe past that desktop. At first this
looked tied to Chrome, but only because Chrome was on desktop 6. A window log showed the HUD's x position at multiples of the
screen width, sliding during the swipe. A private Space query (window and Space ids only) showed the HUD panel, and the tour's
menu bar spotlight panel, each on Space 3 alone, which is desktop 6. Both have `canJoinAllSpaces`. Checked and ruled out: a Mission
Control "Assign To" desktop binding (none), and the Dock icon mode switch (`.regular` ↔ `.accessory`), which left a test panel on
all 8 Spaces. A fresh panel with Dami's exact settings joins all 8. In a test where the panel was forced onto one Space, neither
orderOut/orderFront nor setting `collectionBehavior` again (even after clearing it) brought it back. Only a new panel did.
**Still unknown:** what pins it. Since 11/08 the app has gone through many sleeps and wakes; Dock and WindowServer haven't
restarted.

**Worked around in v1.0.1 (2026-11-12):** the HUD drops its panel each time it hides and readies a new one, and the spotlight
makes new panels on each show. Owner tested right after the build: the HUD shows and animates in on several desktops, desktop 6
included, also in quick repeats and while swiping. **Not verified:** whether it stays right after days of running and many
sleeps, which is when it broke. The cause is still unknown. If it comes back, the same Space query will show whether a new panel
gets pinned too.

**Unrelated, seen at the same time:** the menu bar item sometimes disappears when an app with many menus (cmux, Cursor) is in
front. That's macOS hiding status items behind the notch. Dami's item sits just right of it.

## A mixed dictation sometimes comes out all in one language (2026-11-09)

**Reported by the owner:** a dictation that started in English and went on in Korean came out entirely in English, as if the Korean
part had been translated, and was labelled EN rather than MIXED. Sometimes it goes the other way and comes out all in Korean. Not
measured: how often, and which dictation it was (the latency samples hold languages, not text).

**A guess, not checked:** in Auto, detection picks one language for the whole recording, and Whisper is then run in that language.
Run in English on Korean speech, Whisper tends to translate rather than transcribe; run in Korean, English words can come out in
Hangul. The language-adaptive prompt (`PLAN.md` §5) is meant to keep both, and may not be enough when the first seconds are clearly
one language. To discuss with the owner before any change (2026-11-09).

**Measured on public data (2026-11-15, `bench/lid_results.md`):** 5,619 clips in 9 languages, none of the owner's. Wrong choices
cost both ways: pure English forced to the second language comes out garbled or translated (22.5% error, 21.7% severe). Clear cases
are fine; the failures sit where the two detection scores are close, and more often in short mixed speech (3–5 s). There the higher
score is often the wrong one, so moving the threshold doesn't help.

**Changed in v1.1 (2026-11-15):** when the margin is in −3..7, Dami transcribes in both languages and keeps the text Whisper is more
confident of (mean log probability per text token). Tuned on ko, zh, es, de, checked unchanged on ja, fr, pt, hi, vi: severe failures
3.4% → 1.6% and 4.1% → 3.4%, no language worse. Costs about 1 s, only when unsure. Not yet seen in real use: in the owner's first
four dictations after install, none was unsure (`compared=0` in the latency log). Unverified: the English run in the app carries the
Dictionary prompt, the benchmark's did not; all benchmark data is read speech with 1–4 speakers per language pair.
