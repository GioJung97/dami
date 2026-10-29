#!/usr/bin/env python3
"""Score bench/results/*.jsonl against bench/prompts.tsv and write bench/results.md.

Metrics (lower error is better):
  en  → WER  (word error rate)
  ko  → CER  (character error rate, spaces ignored so 띄어쓰기 differences don't count)
  mixed → CER, plus "EN kept": % of English words in the reference that came out in
          Latin script (not translated or written in Hangul)
Fillers (um, uh, 음, 어…) are removed from both sides before scoring: the speech model
is judged on words, cleanup is Phase 3's job.
Latency = seconds to transcribe after the clip ends (model already loaded).
"""
import csv
import json
import os
import re
import statistics
import sys
from pathlib import Path

BENCH = Path(__file__).resolve().parent
RESULTS = Path(os.environ.get("BENCH_RESULTS", BENCH / "results"))
FILLERS = {"um", "uh", "er", "ah", "hmm", "mm", "음", "어", "으", "아"}


def normalize(text):
    t = text.lower().replace("p.m.", "pm").replace("a.m.", "am")
    t = re.sub(r"\b(\d{1,2}):00\b", r"\1", t)  # "3:00" == "3"
    t = re.sub(r"[^\w\s]", " ", t)  # drop punctuation, keep letters/digits/Hangul
    return [w for w in t.split() if w not in FILLERS]


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def error_rate(ref, hyp, lang):
    r, h = normalize(ref), normalize(hyp)
    if lang == "en":
        return edit_distance(r, h), len(r)
    r, h = "".join(r), "".join(h)
    return edit_distance(r, h), len(r)


def english_kept(ref, hyp):
    words = re.findall(r"[A-Za-z]+", ref)
    hyp_l = hyp.lower()
    return sum(w.lower() in hyp_l for w in words), len(words)


def main():
    with open(BENCH / "prompts.tsv", encoding="utf-8") as f:
        prompts = {p["id"]: p for p in csv.DictReader(f, delimiter="\t")}
    files = sorted(RESULTS.glob("*.jsonl"))
    if not files:
        sys.exit("No results yet. Run: python3 bench/run.py")

    summary, details = [], []
    for path in files:
        name = path.stem
        rows = [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines()]
        meta_path = RESULTS / f"{name}.meta.json"
        meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
        agg = {g: [0, 0] for g in ("en", "ko", "mixed")}
        kept = [0, 0]
        for r in rows:
            p = prompts[r["id"]]
            e, n = error_rate(p["text"], r["text"], p["lang"])
            agg[p["lang"]][0] += e
            agg[p["lang"]][1] += n
            if p["lang"] == "mixed":
                k, m = english_kept(p["text"], r["text"])
                kept[0] += k
                kept[1] += m
            details.append((name, r["id"], p["text"], r["text"], e / max(n, 1)))
        pct = lambda a: f"{100 * a[0] / a[1]:.1f}%" if a[1] else "–"
        lat = [r["latency_s"] for r in rows]
        summary.append([name, pct(agg["en"]), pct(agg["ko"]), pct(agg["mixed"]), pct(kept),
                        f"{statistics.median(lat):.2f}s", f"{max(lat):.2f}s",
                        f"{meta.get('peak_added_mb', '–')} MB", f"{meta.get('min_free_pct', '–')}%"])

    head = ["config", "EN WER", "KO CER", "MIXED CER", "EN kept", "latency (median)", "latency (max)", "RAM added (peak)", "min free"]
    lines = ["# Phase 0 benchmark results", "",
             "| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
    lines += ["| " + " | ".join(row) + " |" for row in summary]
    lines += ["", "## Clips with errors", "", "| config | id | reference | transcript | err |", "|---|---|---|---|---|"]
    lines += [f"| {c} | {i} | {ref} | {hyp} | {e:.0%} |" for c, i, ref, hyp, e in details if e > 0]
    out = "\n".join(lines) + "\n"
    RESULTS.with_suffix(".md").write_text(out, encoding="utf-8")
    print("\n".join(lines[:4 + len(summary)]))
    print(f"\nFull report: {RESULTS.with_suffix('.md')}")


if __name__ == "__main__":
    main()
