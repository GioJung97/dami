#!/usr/bin/env python3
"""Turn the public datasets in bench/data/ into manifests for bench/lideval (v1.1 language choice).

Usage: bench/.venv/bin/python -I bench/lid_manifest.py
Writes bench/data/manifests/<source>.jsonl and the audio as 16 kHz-or-native WAV files under bench/data/wav/<source>/.
Each manifest line: id, audio, l2, prompt, plus what scoring needs: reference text, kind, source, speaker if known.

Sources (downloaded once, git-ignored, never committed):
  hike       thetaone-ai/HiKE (Apache-2.0): Korean-English code-switching, 13 speakers, tagged word / phrase / sentence.
  cs-fleurs  byan/cs-fleurs read/test (CC BY-NC 4.0): X-English code-switching read by bilingual speakers, 14 pairs.
  fleurs     google/fleurs test (CC BY 4.0): one language per clip, many speakers. Pure English and pure second language.
"""
import io
import json
import re
import sys
import tarfile
import wave
from pathlib import Path

BENCH = Path(__file__).resolve().parent
DATA = BENCH / "data"
OUT = DATA / "manifests"
WAV = DATA / "wav"

# The app's mixed prompts (DamiCore/Sources/DamiCore/SpokenLanguage.swift). Keep in sync.
PROMPTS = {
    "ko": "오늘 meeting에서 project timeline 얘기했고, API 관련 bug는 다음 sprint에 fix 할게요.",
    "ja": "今日のmeetingでproject timelineについて話して、APIのbugは次のsprintでfixします。",
    "zh": "今天的meeting我们讨论了project timeline，API的bug下个sprint再fix。",
    "es": "Hoy en el meeting hablamos del project timeline, y el bug de la API lo arreglo en el próximo sprint.",
    "fr": "Aujourd'hui en meeting on a parlé de la project timeline, et je fixe le bug de l'API au prochain sprint.",
    "de": "Heute im Meeting haben wir über die Project Timeline gesprochen, den API-Bug fixe ich im nächsten Sprint.",
    "pt": "Hoje no meeting falamos da project timeline, e o bug da API eu corrijo no próximo sprint.",
    "vi": "Hôm nay trong meeting mình đã nói về project timeline, còn bug của API thì sprint sau mình fix.",
    "hi": "आज की meeting में हमने project timeline पर बात की, API का bug अगले sprint में fix करेंगे।",
}

# CS-FLEURS / FLEURS language names → Whisper codes, for languages the app offers.
ISO3 = {"kor": "ko", "jpn": "ja", "cmn": "zh", "spa": "es", "fra": "fr", "deu": "de", "por": "pt", "hin": "hi"}
FLEURS = {"ko_kr": "ko", "cmn_hans_cn": "zh", "ja_jp": "ja", "es_419": "es", "fr_fr": "fr", "de_de": "de", "pt_br": "pt",
          "hi_in": "hi", "vi_vn": "vi"}


def write(source, lines):
    OUT.mkdir(parents=True, exist_ok=True)
    with open(OUT / f"{source}.jsonl", "w") as f:
        for line in lines:
            f.write(json.dumps(line, ensure_ascii=False) + "\n")
    print(f"{source}: {len(lines)} clips")


def hike():
    import pyarrow.parquet as pq
    path = DATA / "hike/data/test-00000-of-00001.parquet"
    if not path.exists():
        return
    folder = WAV / "hike"
    folder.mkdir(parents=True, exist_ok=True)
    lines = []
    for row in pq.read_table(path).to_pylist():
        audio = folder / f"{row['sample_id']}.wav"
        if not audio.exists():
            audio.write_bytes(row["audio"]["bytes"])
        lines.append({
            "id": f"hike/{row['sample_id']}", "audio": str(audio), "l2": "ko", "prompt": PROMPTS["ko"],
            "source": "hike", "kind": f"cs-{row['cs_level']}", "reference": row["text"],
            "loanwords": json.loads(row["loanwords"] or "[]"), "category": row["category"],
        })
    write("hike", lines)


def cs_fleurs():
    root = DATA / "cs-fleurs/read/test"
    if not root.exists():
        return
    lines = []
    for meta in sorted(root.rglob("metadata.jsonl")):
        for raw in meta.read_text().splitlines():
            row = json.loads(raw)
            code = ISO3.get(row["language"].split("-")[0])  # "kor-eng"
            audio = meta.parent / row["file_name"]
            if not code or not audio.exists():
                continue
            lines.append({
                "id": f"cs-fleurs/{row['id']}", "audio": str(audio), "l2": code, "prompt": PROMPTS[code],
                "source": "cs-fleurs", "kind": "cs-read", "reference": row["text"], "speaker": f"{code}-{row['speaker']}",
            })
    write("cs-fleurs", lines)


def fleurs(limit_per_language=200):
    root = DATA / "fleurs/data"
    if not root.exists():
        return
    lines = []
    for folder in sorted(root.iterdir()):
        tsv, tar = folder / "test.tsv", folder / "audio/test.tar.gz"
        if not (tsv.exists() and tar.exists()):
            continue
        name = folder.name
        lang = "en" if name == "en_us" else FLEURS.get(name)
        if not lang:
            continue
        rows = {}
        for raw in tsv.read_text().splitlines():
            cols = raw.split("\t")
            rows.setdefault(cols[1], (cols[0], cols[2], cols[-2] if len(cols) > 6 else ""))  # file → (id, transcription, gender)
        out = WAV / "fleurs" / name
        out.mkdir(parents=True, exist_ok=True)
        picked = []
        seen_sentences = set()
        with tarfile.open(tar) as t:
            for member in t:
                base = Path(member.name).name
                if base not in rows or rows[base][0] in seen_sentences:
                    continue
                seen_sentences.add(rows[base][0])  # one reading per sentence, so no sentence counts twice
                path = out / base
                if not path.exists():
                    path.write_bytes(t.extractfile(member).read())
                picked.append((base, path))
                if len(picked) >= limit_per_language:
                    break
        # English clips are scored once per second language: what happens to pure English when that language is set.
        targets = sorted(PROMPTS) if lang == "en" else [lang]
        for base, path in picked:
            for l2 in targets:
                lines.append({
                    "id": f"fleurs/{name}/{base}/{l2}", "audio": str(path), "l2": l2, "prompt": PROMPTS[l2],
                    "source": "fleurs", "kind": "pure-en" if lang == "en" else "pure-l2", "reference": rows[base][1],
                })
    write("fleurs", lines)


if __name__ == "__main__":
    for step in (sys.argv[1:] or ["hike", "cs_fleurs", "fleurs"]):
        globals()[step.replace("-", "_")]()
