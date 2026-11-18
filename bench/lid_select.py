#!/usr/bin/env python3
"""Can Whisper's own confidence pick between the English run and the second-language run when detection is unsure? (v1.1)

Usage: bench/.venv/bin/python -I bench/lid_select.py
Reads bench/data/runs-stats/*.jsonl (lideval --decode-only on clips whose detection margin was near zero) and the detection
scores from bench/data/runs/. Prints a table; nothing is written.

Every selector runs only inside a margin band; outside it the app's rule stands. Its settings are chosen on the dev languages
(ko, zh, es, de) and then judged unchanged on the held-out ones (ja, fr, pt, hi, vi), so a selector that only fits Korean shows.
"""
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lid_score as s  # noqa: E402

DEV = {"ko", "zh", "es", "de"}
TEST = {"ja", "fr", "pt", "hi", "vi"}


def load():
    meta = {}
    for path in (s.DATA / "manifests").glob("*.jsonl"):
        for line in path.read_text().splitlines():
            row = json.loads(line)
            meta[row["id"]] = row
    detect = {}
    for path in (s.DATA / "runs").glob("*.jsonl"):
        if path.stem == "smoke":
            continue
        for line in path.read_text().splitlines():
            row = json.loads(line)
            detect[row["id"]] = row["whole"]
    clips = []
    for path in (s.DATA / "runs-stats").glob("*.jsonl"):
        for line in path.read_text().splitlines():
            run = json.loads(line)
            if run["id"] in meta and run["id"] in detect:
                clips.append({**meta[run["id"]], **run, "whole": detect[run["id"]]})
    return clips


def l2_run(c):
    """The second-language run the app would paste, after its script safety net."""
    run = c["forcedL2Prompt"]
    script = s.SCRIPTS.get(c["l2"])
    if script and run["text"] and not re.search(script, run["text"]):
        return c["forcedL2NoPrompt"]
    return run


def avg(run):
    st = run["stats"]
    return st["textLogprob"] / st["textTokens"] if st["textTokens"] else -99.0


def features(c):
    en, l2 = c["forcedEN"], l2_run(c)
    return {
        "margin": s.margin(c["whole"]),
        "avg": avg(l2) - avg(en),  # >0: the second-language text is more confident per token
        "minavg": l2["stats"]["minAvgLogprob"] - en["stats"]["minAvgLogprob"],
        "fallback": (l2["stats"]["maxTemperature"] > 0) - (en["stats"]["maxTemperature"] > 0),  # >0: only L2 fell back
    }


def score_clips(clips):
    for c in clips:
        loan = c.get("loanwords") or ()
        ref = s.normalize(c["reference"], loan)
        c["err"] = {False: s.cer(ref, s.normalize(c["forcedEN"]["text"], loan)),
                    True: s.cer(ref, s.normalize(l2_run(c)["text"], loan))}
        c["f"] = features(c)


def today(c):
    return c["f"]["margin"] < 0


# Selectors: (name, settings grid, pick(c, settings) → True for the second language)
def selectors():
    bands = [(-3, 7), (-2, 5), (-1, 3), (-5, 9)]
    out = [("app today", [None], lambda c, p: today(c))]
    out.append(("higher avg logprob per token", [(b, 0.0) for b in bands],
                lambda c, p: c["f"]["avg"] > p[1] if p[0][0] <= c["f"]["margin"] <= p[0][1] else today(c)))
    out.append(("avg logprob + bias", [(b, t) for b in bands for t in (-0.3, -0.2, -0.1, -0.05, 0.05, 0.1, 0.2)],
                lambda c, p: c["f"]["avg"] > p[1] if p[0][0] <= c["f"]["margin"] <= p[0][1] else today(c)))
    out.append(("avg logprob + margin", [(b, w) for b in bands for w in (0.01, 0.02, 0.05, 0.1)],
                lambda c, p: c["f"]["avg"] - p[1] * c["f"]["margin"] > 0 if p[0][0] <= c["f"]["margin"] <= p[0][1] else today(c)))
    out.append(("worst segment avg logprob", [(b, 0.0) for b in bands],
                lambda c, p: c["f"]["minavg"] > p[1] if p[0][0] <= c["f"]["margin"] <= p[0][1] else today(c)))
    out.append(("avoid the run that fell back, else today", [(b, 0) for b in bands],
                lambda c, p: (c["f"]["fallback"] < 0 if c["f"]["fallback"] else today(c))
                if p[0][0] <= c["f"]["margin"] <= p[0][1] else today(c)))
    out.append(("oracle (best of two)", [None], lambda c, p: c["err"][True] < c["err"][False]))
    return out


def summary(subset, pick, p):
    errs = [c["err"][pick(c, p)] for c in subset]
    return sum(errs) / len(errs), sum(e > 0.5 for e in errs) / len(errs)


def band_cost(subset, p):
    if not p or not isinstance(p[0], tuple):
        return 0.0
    return sum(p[0][0] <= c["f"]["margin"] <= p[0][1] for c in subset) / len(subset)


def main():
    clips = load()
    if not clips:
        sys.exit("no runs-stats yet")
    score_clips(clips)
    dev = [c for c in clips if c["l2"] in DEV]
    test = [c for c in clips if c["l2"] in TEST]
    print(f"clips: {len(clips)} (dev {len(dev)}, held-out {len(test)}); all had detection margin in −5..9\n")
    print("Settings chosen on dev by severe share, then mean error. Cells: mean error / severe. "
          "'two runs' = share of these clips that would pay for a second transcription.\n")
    print(f"| selector | settings | dev | held-out | held-out pure-en | held-out mixed | two runs |")
    print("|---|---|---|---|---|---|---|")
    for name, grid, pick in selectors():
        best = min(grid, key=lambda p: (summary(dev, pick, p)[1], summary(dev, pick, p)[0]))
        cells = []
        for subset in (dev, test, [c for c in test if c["kind"] == "pure-en"], [c for c in test if c["kind"] != "pure-en"]):
            if subset:
                m, sv = summary(subset, pick, best)
                cells.append(f"{m:.1%} / {sv:.1%} (n={len(subset)})")
            else:
                cells.append("–")
        print(f"| {name} | {best} | " + " | ".join(cells) + f" | {band_cost(clips, best):.0%} |")

    # Per kind and language for the chosen avg-logprob selector, so a language it hurts shows.
    print("\nBy second language and kind (dev rows were used for tuning):\n")
    sel = {n: (g, p) for n, g, p in selectors()}
    name = "avg logprob + bias"
    grid, pick = sel[name]
    best = min(grid, key=lambda p: (summary(dev, pick, p)[1], summary(dev, pick, p)[0]))
    groups = defaultdict(list)
    for c in clips:
        groups[(c["l2"], c["kind"])].append(c)
    print(f"| lang | kind | n | today | {name} {best} | oracle |")
    print("|---|---|---|---|---|---|")
    for key in sorted(groups):
        sub = groups[key]
        t = summary(sub, sel["app today"][1], None)
        a = summary(sub, pick, best)
        o = summary(sub, sel["oracle (best of two)"][1], None)
        print(f"| {key[0]}{'' if key[0] in DEV else ' (held-out)'} | {key[1]} | {len(sub)} | {t[0]:.1%} / {t[1]:.1%} | "
              f"{a[0]:.1%} / {a[1]:.1%} | {o[0]:.1%} / {o[1]:.1%} |")


if __name__ == "__main__":
    main()
