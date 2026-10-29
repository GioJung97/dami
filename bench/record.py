#!/usr/bin/env python3
"""Record the evaluation clips: shows each prompt, Enter to start, Enter to stop.

Usage:
  python3 bench/record.py --list-devices
  python3 bench/record.py --device 0            # record all missing clips
  python3 bench/record.py --device 0 --redo ko05
"""
import argparse
import csv
import subprocess
import sys
from pathlib import Path

BENCH = Path(__file__).resolve().parent
CLIPS = BENCH / "clips"


def load_prompts():
    with open(BENCH / "prompts.tsv", encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def list_devices():
    out = subprocess.run(
        ["ffmpeg", "-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""],
        capture_output=True, text=True,
    ).stderr
    in_audio = False
    for line in out.splitlines():
        if "audio devices" in line:
            in_audio = True
            continue
        if in_audio and "] [" in line:
            print(line.split("] ", 1)[1])


def record(device, path):
    proc = subprocess.Popen(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
         "-f", "avfoundation", "-i", f":{device}",
         "-ac", "1", "-ar", "16000", "-sample_fmt", "s16", str(path)],
        stdin=subprocess.PIPE,
    )
    input("  🔴 Recording… press Enter to stop ")
    proc.communicate(b"q")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", help="audio device index (see --list-devices)")
    ap.add_argument("--list-devices", action="store_true")
    ap.add_argument("--redo", nargs="*", default=[], help="clip ids to re-record")
    args = ap.parse_args()

    if args.list_devices or args.device is None:
        list_devices()
        if args.device is None:
            print("\nRe-run with --device <index>")
        return

    CLIPS.mkdir(exist_ok=True)
    prompts = load_prompts()
    todo = [p for p in prompts if p["id"] in args.redo or not (CLIPS / f"{p['id']}.wav").exists()]
    print(f"{len(todo)} clip(s) to record. Speak naturally; read fillers (um, 음…) as written.\n"
          "Commands at the prompt: Enter = start, s = skip, q = quit.\n")

    for i, p in enumerate(todo, 1):
        path = CLIPS / f"{p['id']}.wav"
        while True:
            print(f"[{i}/{len(todo)}] {p['id']} ({p['lang']})\n  » {p['text']}")
            cmd = input("  Enter to start: ").strip().lower()
            if cmd == "q":
                return
            if cmd == "s":
                break
            record(args.device, path)
            subprocess.run(["afplay", str(path)])
            if input("  Keep it? [Y/n] ").strip().lower() != "n":
                break
        print()
    print(f"Done. Clips in {CLIPS}")


if __name__ == "__main__":
    sys.exit(main())
