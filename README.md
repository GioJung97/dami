# LocalFlow

Offline dictation for macOS. Hold a key, speak, and the text is pasted at your cursor. Speech recognition runs
on your Mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit). There's no account and no subscription,
and your voice isn't uploaded.

It handles English and one other language, including both in the same sentence, with English words kept in English.
It's an early version, built for its author's daily use. It learns from your fixes, and only changes what you approve.

## Requirements

- Apple Silicon Mac, macOS 14 or newer. So far tested on macOS 15.3 only.
- Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and an Apple Development certificate, to build it.
  There's no prebuilt download yet.
- About 1 GB free for the speech model (632 MB), which downloads once on first launch.

## Build from source

```bash
brew install xcodegen
# Xcode → Settings → Accounts → your Apple ID → Manage Certificates → + → Apple Development
scripts/build.sh          # Release build, installs to /Applications/LocalFlow.app and launches it
```

Keep the same certificate and install path, so macOS keeps the permissions across rebuilds.

Run the tests with `swift test --package-path LocalFlowCore`.

## Permissions

| Permission | Why |
|---|---|
| Microphone | To hear you while you hold the shortcut |
| Input Monitoring | Asked for only if the shortcut doesn't start with Accessibility alone. It wasn't needed on the one Mac tested (macOS 15.3) |
| Accessibility | To notice the shortcut in any app, to paste with ⌘V, and to read the one character before the cursor when deciding on a space. With Learn from fixes on, also to read the text of the field it pasted into, about once a second for up to 2 minutes, to see if you fix it |

## Using it

- Hold **Right ⌘ + Right ⌥** to talk, and let go to paste. The shortcut can be changed in Settings, along with an
  option to double-tap for hands-free.
- Press Esc to cancel. A recording stops on its own after 5 minutes and is transcribed.
- **Light** mode (the default) removes fillers such as "um" and "음" and some repeated words, keeps a corrected number
  ("3, no, 4" becomes "4"), and applies your Dictionary. **Raw** pastes exactly what Whisper wrote.
- If nothing was recognized in a recording of a second or more, the HUD offers **Retry**, which tries the other language. A
  recording dropped as a phrase Whisper often makes up on silence, such as "Thanks for watching", offers **Paste anyway**.

## Learning from your fixes

LocalFlow doesn't retrain Whisper. It learns around it, and only changes anything when you approve.

- **Fix in History.** Open a dictation, choose Fix…, and save what you meant. History, search, Copy and paste again use the fix,
  with the pasted text kept below it. The pencil on a Recent item in the menu opens the same box.
- **Fixes where you pasted.** In apps whose text Accessibility can read (Notes, browser text boxes, Terminal), a fix you make to the
  pasted text within 2 minutes is saved the same way. It stops watching when you switch app or field, dictate again, or a password
  field is in use. Some apps can't be read, such as cmux and Google Docs; use Fix in History there.
- **Suggestions.** After a fix that changes one to three words, LocalFlow asks "Always fix X → Y?", with how many past dictations
  have it and which words it would touch. Approving adds a Replacement for future dictations. "Not this" isn't asked again. Fixes
  seen where you pasted need the same fix twice, on a word Whisper was unsure of, and wait in Dictionary › Suggestions. One-syllable
  Korean fixes aren't suggested, since a rule like "세 → 네" is too likely to hit something else.
- **This is what I said.** On a dictation with saved audio, it marks the text as a correct transcript and keeps the audio past
  retention, until you unmark or delete it. These pairs are for testing accuracy later.
- **How Replacements match.** Whole words, ignoring case, in languages that put spaces between words. Korean also matches with up
  to two particles after, so a rule for "클라우드" changes "클라우드에서도" but not "클라우드펀딩". Japanese, Chinese and Thai match
  anywhere in the text, since words there aren't spaced.

## Privacy

- Speech and text stay on your Mac. The network is only used to download the speech model.
- Text history is stored unencrypted in `~/Library/Application Support/LocalFlow/` until you delete it. By default it's
  kept forever. You can change that in Settings → Privacy, including turning history off.
- Audio is only saved if you turn that on. It's kept for 7, 30 or 90 days.
- Clipboard: pasting briefly uses the clipboard, then restores what was there. That temporary text is marked so clipboard
  history apps can skip it, if they honor the marker. When there's nowhere to paste, the text stays on the clipboard as a
  normal copy.
- Only a single "a key was pressed" flag is kept, and only in memory, to decide on a space. Which key is never recorded.
- **Learn from fixes** is on by default and can be turned off in Settings → Privacy. Of the field it reads, it keeps only the text
  it pasted and what that became, never the text around it, and nothing from password fields. Fixes are deleted with their
  dictation, and follow the history setting.
- Deleting history overwrites the deleted text in the database file. **Delete all history** also removes the backup and rewrites
  the file.
- Before the database format changes in an update, a backup copy is made next to it (`LocalFlow.backup.sqlite`). It's deleted 7
  days later.
- A recording offered for Retry or Paste anyway stays in memory only, three at most, and is gone when the app quits.

## Languages

| Language | Status |
|---|---|
| English | Tested on real recordings |
| Korean | Tested on real recordings |
| Japanese, Chinese, Spanish, French, German, Portuguese, Vietnamese, Hindi | **Experimental.** Their prompts haven't been tested on real voices |

Cleanup rules exist for English and Korean only. Spanish, French, German, Portuguese and Vietnamese get no rules, since
words like German "er" and Portuguese "um" are real words there.

## Known limitations

- Whisper transcribes one language at a time, so the same word can come out in either language. Mixed sentences are less
  accurate than single-language ones.
- Bluetooth microphones are unreliable. With AirPods, dictations often produced nothing in testing, and first words can
  be cut. The built-in or a wired microphone is recommended.
- Rules are deliberately narrow, so some fillers stay ("like", "어"), and sentences aren't rewritten.
- In fields Accessibility can't read, such as terminals, spacing between dictations is a best guess. It can miss a space
  after 2 minutes, and moving the cursor with the mouse alone can add an extra one.
- A green check means the paste was sent. In some apps, when no text field is focused, the text may not appear. It's still in
  History and in the menu's Recent list. See [known issues](docs/known-issues.md) for how to report it.
- Vocabulary in the Dictionary only helps English dictations. For other languages, use Replacements.
- Learning from fixes where you pasted only works in apps Accessibility can read. A fix seen there is matched by position, so an
  edit that crosses the edge of the pasted text isn't saved.
- Some screens show features that aren't built yet, marked as coming later.

## License

[MIT](LICENSE). WhisperKit and GRDB are also MIT licensed.
