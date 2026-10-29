#!/usr/bin/env python3
"""Simulate language-adaptive prompting from existing results (what the app will do):
Whisper detects the language first; English clips use the English-side config, Korean
(incl. mixed) clips use the Korean-side config.

Usage: python3 bench/combine.py <name> <detector-config> <english-config> <korean-config>
"""
import json
import os
import sys
from pathlib import Path

RESULTS = Path(os.environ.get("BENCH_RESULTS", Path(__file__).resolve().parent / "results"))


def load(name):
    return {r["id"]: r for r in map(json.loads, (RESULTS / f"{name}.jsonl").read_text(encoding="utf-8").splitlines())}


def main():
    name, detector, en_cfg, ko_cfg = sys.argv[1:5]
    det, en, ko = load(detector), load(en_cfg), load(ko_cfg)
    with open(RESULTS / f"{name}.jsonl", "w", encoding="utf-8") as f:
        for cid, d in det.items():
            f.write(json.dumps((en if d["language"] == "en" else ko)[cid], ensure_ascii=False) + "\n")
    metas = [json.loads((RESULTS / f"{c}.meta.json").read_text()) for c in (en_cfg, ko_cfg)]
    meta = {"combined": [en_cfg, ko_cfg], "detector": detector,
            "peak_added_mb": max(m["peak_added_mb"] for m in metas),
            "min_free_pct": min(m["min_free_pct"] for m in metas)}
    (RESULTS / f"{name}.meta.json").write_text(json.dumps(meta, indent=2))
    print(f"wrote {name}")


if __name__ == "__main__":
    main()
