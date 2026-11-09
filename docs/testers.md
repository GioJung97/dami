# Trying Dami: a note for testers

Thanks for trying Dami before its first official version. Please read this before installing, and only install if you're fine
with it.

## What it is

Dami is offline dictation for macOS. Hold **Right ⌘ + Right ⌥**, speak English, your other language, or both mixed, and let go:
the text is pasted where your cursor is. Speech recognition runs on your Mac. It's an early version, built for one person's
daily use, so expect rough edges.

You need an Apple Silicon Mac with macOS 14 or newer, and about 1 GB free for the speech model, downloaded once at setup.
Install steps are in the [README](../README.md#from-a-dmg). Dami isn't notarized by Apple, so the first open needs
**Open Anyway** in System Settings.

## What stays on your Mac

- Your voice and text never leave your Mac. The network is only used once, to download the speech model.
- History of what you dictated is kept in `~/Library/Application Support/Dami/`, unencrypted, until you delete it. Settings ›
  Privacy can shorten it or turn it off. Audio is only kept if you turn that on.
- Learn from fixes (on by default, can be turned off in Settings › Privacy) reads the text field it pasted into for up to 2
  minutes, to notice your fixes. It keeps only the pasted text and what it became.
- The [README's Privacy section](../README.md#privacy) has the details.

## How long

There's no fixed period. Use it as you would normally, for as long as you like. When you've used it enough, send the diagnostics
file (below). Telling us when something went wrong helps most: no text, text in the wrong place, the wrong language, or slowness.

## The diagnostics file

Settings › Privacy › Diagnostics › **Export diagnostics…** shows the whole file before you save it, so you can read everything
you send. It holds:

- the Dami and macOS versions and the Mac model;
- your settings as names only (for example the cleanup mode, or whether the shortcut is the default or a custom one);
- counts of failed or dropped dictations by day, and how each "Learn from fixes" watch ended;
- the stage timings of the last 100 dictations, in seconds, with their audio length and language;
- whether the database passed its check, and how many dictations it holds;
- the file names of any Dami crash reports.

It never holds what you dictated, your Dictionary, device names or which keys you pressed. Send it to the person who gave you
Dami, any way you like.

## If you use AirPods or another Bluetooth headset

Using a Bluetooth headset's microphone works but is slower to start: the headset switches to call mode, which takes 1–2 seconds,
and lowers its sound quality while you dictate. For quicker starts, choose your Mac's built-in microphone in Dami's menu ›
Microphone, and keep listening on the headset.

## To stop

Quit Dami from its menu bar icon, then move Dami from Applications to the Bin. To also remove its data and the speech model,
delete `~/Library/Application Support/Dami/`.
