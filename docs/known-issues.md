# Known issues

Things we know about and chose not to chase yet. When someone reports one, start here.

## Green check, but the text didn't appear

**What happens:** LocalFlow shows the check, but nothing shows up in the app. The check only means ⌘V was sent. Accessibility
said the focused element could take text, and it couldn't. The speech isn't lost: it's in History and in the menu's Recent list.

**Why it isn't fully solved:** apps describe their focused element in different ways, so `FocusClassifier` (in `LocalFlowCore`)
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
   log stream --level debug --predicate 'subsystem == "com.localflow.app" AND category == "insertion"'
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

The owner reports that very short speech is often recognized poorly (2026-11-04). Not investigated or measured yet, and to be
looked at on its own later. Starting points, none confirmed: presses under 0.3 s are dropped as accidental, the mic takes
0.13–0.18 s to start so the first sound may be cut, the hallucination filter removes some short outputs, and Whisper has little
context to work with. A short Korean test clip also returned no words on its first run in M7.

## Made-up text during long pauses

In a 10:39 hands-free recording where the owner spoke a few words, waited and spoke again, text that wasn't said appeared in the
result (2026-11-04). The owner spoke only a few words in that time and considers this expected, not a bug: not investigated, and
to be reopened only if it shows up in real use. The hallucination filter only checks a whole output, so it can't remove a made-up
part inside real speech.
