#!/usr/bin/env python3
"""Run each speech-to-text configuration over bench/clips and save results.

Usage:
  python3 bench/run.py                 # run the light configs (632 MB turbo, ± prompt)
  python3 bench/run.py wk-turbo wcpp-turbo   # heavier configs only when named
Runs one config at a time and aborts if free system memory drops below MIN_FREE_PCT.
Results: bench/results/<config>.jsonl  (one line per clip: id, text, language, latency_s, audio_s)
         bench/results/<config>.meta.json (model, peak system RAM added, min free %)
"""
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
import uuid
import wave
from pathlib import Path

BENCH = Path(__file__).resolve().parent
CLIPS = Path(os.environ.get("BENCH_CLIPS", BENCH / "clips"))
RESULTS = Path(os.environ.get("BENCH_RESULTS", BENCH / "results"))
MODELS = BENCH / "models"

# A short mixed Korean/English sample in a dictation style. Biases Whisper to keep
# English terms in Latin script inside Korean sentences.
MIXED_PROMPT = "오늘 meeting에서 project timeline 얘기했고, API 관련 bug는 다음 sprint에 fix 할게요."

# Stand-in for the personal dictionary (PLAN §4.2): terms Whisper keeps misspelling.
VOCAB = "Supabase, Vercel, Claude Code, pull request, commit, deploy, refactoring."

# The same vocabulary woven into a Korean sentence. An English-only word list after the
# Korean sample pushes Whisper into English and it translates Korean speech (seen on mx06).
VOCAB_MIXED = ("오늘 meeting에서 project timeline 얘기했고, Supabase migration이랑 Vercel deploy는 "
               "Claude Code로 refactoring 한 다음에 pull request 올리고 commit 할게요.")

CONFIGS = {
    "wk-turbo":       {"engine": "whisperkit", "model": "large-v3-v20240930_turbo"},
    "wk-turbo-prompt": {"engine": "whisperkit", "model": "large-v3-v20240930_turbo", "prompt": MIXED_PROMPT},
    "wk-turbo-632mb": {"engine": "whisperkit", "model": "large-v3-v20240930_turbo_632MB"},
    "wk-turbo-632mb-prompt": {"engine": "whisperkit", "model": "large-v3-v20240930_turbo_632MB", "prompt": MIXED_PROMPT},
    "wk-turbo-632mb-vocab-en": {"engine": "whisperkit", "model": "large-v3-v20240930_turbo_632MB", "prompt": VOCAB},
    "wk-turbo-632mb-vocab-mixed": {"engine": "whisperkit", "model": "large-v3-v20240930_turbo_632MB",
                                   "prompt": MIXED_PROMPT + " " + VOCAB},
    "wk-turbo-632mb-vocab-mixed-ko": {"engine": "whisperkit", "model": "large-v3-v20240930_turbo_632MB",
                                      "prompt": MIXED_PROMPT + " " + VOCAB, "language": "ko"},
    "wk-turbo-632mb-vocab-ko-sentence": {"engine": "whisperkit", "model": "large-v3-v20240930_turbo_632MB",
                                         "prompt": VOCAB_MIXED},
    "wk-large-v3":    {"engine": "whisperkit", "model": "large-v3"},
    "wcpp-turbo":     {"engine": "whispercpp", "model": "ggml-large-v3-turbo.bin"},
}

# Run by default. The others are heavier (wk-large-v3 made the Mac lag) and run only when named.
LIGHT = ["wk-turbo-632mb", "wk-turbo-632mb-prompt"]
MIN_FREE_PCT = 15

WCPP_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"


def audio_seconds(path):
    with wave.open(str(path)) as w:
        return w.getnframes() / w.getframerate()


def system_used_bytes():
    """Active + wired + compressed memory. Counts Core ML / Neural Engine memory that a
    process's own RSS misses."""
    out = subprocess.run(["vm_stat"], capture_output=True, text=True).stdout
    page = int(re.search(r"page size of (\d+)", out).group(1))
    pages = {k: int(v) for k, v in re.findall(r"^(.+?):\s+(\d+)\.", out, re.M)}
    keys = ("Pages active", "Pages wired down", "Pages occupied by compressor")
    return page * sum(pages.get(k, 0) for k in keys)


def free_pct():
    out = subprocess.run(["sysctl", "-n", "kern.memorystatus_level"], capture_output=True, text=True)
    return int(out.stdout.strip())


class MemoryGuard(threading.Thread):
    """Samples system memory while a config runs; kills `proc` if free memory gets too low."""

    def __init__(self):
        super().__init__(daemon=True)
        self.baseline = system_used_bytes()
        self.peak = self.baseline
        self.min_free = free_pct()
        self.proc = None
        self.tripped = False
        self._stop = threading.Event()

    def run(self):
        while not self._stop.wait(0.5):
            self.peak = max(self.peak, system_used_bytes())
            self.min_free = min(self.min_free, free_pct())
            if self.min_free < MIN_FREE_PCT and not self.tripped:
                self.tripped = True
                if self.proc:
                    self.proc.kill()

    def stop(self):
        self._stop.set()
        self.join()
        return {"peak_added_mb": round((self.peak - self.baseline) / 2**20), "min_free_pct": self.min_free}


def run_whisperkit(name, cfg, clips, guard):
    report = RESULTS / name
    shutil.rmtree(report, ignore_errors=True)
    report.mkdir(parents=True)
    cmd = ["whisperkit-cli", "transcribe",
           "--model", cfg["model"], "--download-model-path", str(MODELS / "whisperkit"),
           "--audio-folder", str(CLIPS), "--concurrent-worker-count", "1",
           "--report", "--report-path", str(report)]
    if cfg.get("prompt"):
        cmd += ["--prompt", cfg["prompt"]]
    if cfg.get("language"):
        cmd += ["--language", cfg["language"]]
    guard.proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    _, err = guard.proc.communicate()
    if guard.tripped:
        return None
    if guard.proc.returncode != 0:
        sys.exit(f"{name} failed:\n{err[-2000:]}")
    rows = []
    for clip in clips:
        rep = json.loads((report / f"{clip.stem}.json").read_text())
        rows.append({"id": clip.stem, "text": rep["text"].strip(), "language": rep.get("language"),
                     "latency_s": rep["timings"]["fullPipeline"], "audio_s": audio_seconds(clip)})
    return rows


def post_multipart(url, fields, wav_path):
    b = uuid.uuid4().hex
    body = b""
    for k, v in fields.items():
        body += f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
    body += (f'--{b}\r\nContent-Disposition: form-data; name="file"; filename="a.wav"\r\n'
             f"Content-Type: audio/wav\r\n\r\n").encode() + wav_path.read_bytes() + b"\r\n"
    body += f"--{b}--\r\n".encode()
    req = urllib.request.Request(url, body, {"Content-Type": f"multipart/form-data; boundary={b}"})
    return json.load(urllib.request.urlopen(req, timeout=300))


def run_whispercpp(name, cfg, clips, guard):
    model = MODELS / "whispercpp" / cfg["model"]
    if not model.exists():
        model.parent.mkdir(parents=True, exist_ok=True)
        print(f"  downloading {cfg['model']}…")
        subprocess.run(["curl", "-L", "--fail", "-o", str(model), WCPP_URL + cfg["model"]], check=True)
    port = "8178"
    server = guard.proc = subprocess.Popen(["whisper-server", "-m", str(model), "--port", port, "-l", "auto"],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    url = f"http://127.0.0.1:{port}/inference"
    try:
        for _ in range(120):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=1)
                break
            except Exception:
                time.sleep(1)
        fields = {"response_format": "verbose_json", "temperature": "0.0", "language": "auto"}
        if cfg.get("prompt"):
            fields["prompt"] = cfg["prompt"]
        post_multipart(url, fields, clips[0])  # warm-up, not timed
        rows = []
        for clip in clips:
            if guard.tripped:
                return None
            t0 = time.perf_counter()
            res = post_multipart(url, fields, clip)
            rows.append({"id": clip.stem, "text": res["text"].strip(), "language": res.get("language"),
                         "latency_s": time.perf_counter() - t0, "audio_s": audio_seconds(clip)})
    finally:
        server.terminate()
        server.wait()
    return rows


def main():
    clips = sorted(CLIPS.glob("*.wav"))
    if not clips:
        sys.exit("No clips yet. Record them first: python3 bench/record.py --device <n>")
    names = sys.argv[1:] or LIGHT
    RESULTS.mkdir(exist_ok=True)
    for name in names:
        cfg = CONFIGS[name]
        print(f"▶ {name} ({cfg['model']}) on {len(clips)} clips…")
        if free_pct() < MIN_FREE_PCT + 10:
            sys.exit(f"Only {free_pct()}% memory free. Close some apps and re-run.")
        runner = run_whisperkit if cfg["engine"] == "whisperkit" else run_whispercpp
        guard = MemoryGuard()
        guard.start()
        rows = runner(name, cfg, clips, guard)
        meta = guard.stop()
        if rows is None:
            sys.exit(f"Stopped {name}: free memory fell below {MIN_FREE_PCT}%. Nothing saved for it.")
        with open(RESULTS / f"{name}.jsonl", "w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        (RESULTS / f"{name}.meta.json").write_text(json.dumps({**cfg, **meta}, ensure_ascii=False, indent=2))
        print(f"  done. system RAM added ≈ {meta['peak_added_mb']} MB, lowest free {meta['min_free_pct']}%")
    print("Score with: python3 bench/score.py")


if __name__ == "__main__":
    main()
