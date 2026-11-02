# LocalFlow

Offline dictation for macOS. Hold a key, speak, and the text is pasted at your cursor. Speech recognition runs
on your Mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit). There's no account and no subscription,
and your voice isn't uploaded.

It handles English and one other language, including both in the same sentence, with English words kept in English.
It's an early version, built for its author's daily use.

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
| Input Monitoring | To notice the shortcut in any app |
| Accessibility | To paste with ⌘V, and to read the one character before the cursor when deciding on a space |

## Using it

- Hold **Right ⌘ + Right ⌥** to talk, and let go to paste. The shortcut can be changed in Settings, along with an
  option to double-tap for hands-free.
- Press Esc to cancel. A recording stops on its own after 10 minutes and is transcribed.
- **Light** mode (the default) removes fillers such as "um" and "음" and some repeated words, keeps a corrected number
  ("3, no, 4" becomes "4"), and applies your Dictionary. **Raw** pastes exactly what Whisper wrote.

## Privacy

- Speech and text stay on your Mac. The network is only used to download the speech model.
- Text history is stored unencrypted in `~/Library/Application Support/LocalFlow/` until you delete it. By default it's
  kept forever. You can change that in Settings → Privacy, including turning history off.
- Audio is only saved if you turn that on. It's kept for 7, 30 or 90 days.
- Clipboard: pasting briefly uses the clipboard, then restores what was there. That temporary text is marked so clipboard
  history apps can skip it, if they honor the marker. When there's nowhere to paste, the text stays on the clipboard as a
  normal copy.
- Only a single "a key was pressed" flag is kept, and only in memory, to decide on a space. Which key is never recorded.

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
- Some screens show features that aren't built yet, marked as coming later.

## License

[MIT](LICENSE). WhisperKit and GRDB are also MIT licensed.
