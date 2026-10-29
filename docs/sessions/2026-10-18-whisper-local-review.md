# Session notes — 2026-10-18: whisper-local review and plan update

A Claude Code session that compared the open-source **whisper-local** (`drajb/whisper-local`) against
the LocalFlow plan, then updated `PLAN.md`. Written as a handoff so a new session on another Mac can
pick up without the original conversation.

> Work done in later sessions (2026-10-19 to 2026-10-21: recording clips, Phase 0 benchmark, the
> Phase 1–2 Swift app) is recorded in `PLAN.md` status lines and `bench/results.md`, not here.

---

## 1. What was asked

1. Reverse-engineer whisper-local: architecture, how it works.
2. How it differs from LocalFlow, and can it run on this Mac (M4, 16 GB, 10 cores, macOS 27)?
3. Which speech model does it use, and is it local or an API?
4. faster-whisper vs WhisperKit: what's actually different?
5. Should LocalFlow switch to CPU to save memory? How to handle bilingual polishing cheaply?
6. Update `PLAN.md` with the conclusions.

## 2. whisper-local in brief

Python tray app (~14k lines), Windows-first with macOS support. `state_manager.py` drives everything:

```
Hotkey (macOS: CGEventTap, NSEvent fallback)
  → AudioRecorder (sounddevice, 16 kHz, in memory)
  → TEN VAD (skip silence → fewer hallucinations)
  → WhisperEngine (faster-whisper / CTranslate2), or opt-in whisper.cpp backend
  → text_postprocess.py: voice editing ("scratch that", "actually 3") → spoken formatting
    → smart formatting → user corrections → filler strip → lists/style → snippets
    → casing/punctuation → optional Ollama polish (localhost:11434)
  → per-app rules (foreground app → formatting / paste / suppress)
  → clipboard + synthetic ⌘V, restore clipboard
  → history, stats, optional audit log
```

- **Default model:** OpenAI Whisper `base` (141 MB) via faster-whisper, CPU, int8. Also offers tiny →
  large-v3, large-v3-turbo, `.en` and distil variants. Streaming preview (off by default) uses a
  separate English-only Zipformer model via sherpa-onnx.
- **Fully local.** faster-whisper is an in-process library. Network only for the one-time model
  download from HuggingFace, an opt-in update check, and Ollama on localhost (text, not audio).

### Findings that matter for LocalFlow

| Finding | Where |
|---|---|
| faster-whisper is **CPU-only on Mac** (GPU support is CUDA) | `platform/macos/gpu.py` is a no-op |
| whisper.cpp backend (Metal) **stores `initial_prompt`/`hotwords` but never passes them** to the model | `whisper_engine_cpp.py:42-43` vs `:95-102` |
| Filler stripping is English-only regex (`um\|uh\|erm\|uhm\|hmm`), no Korean | `text_postprocess.py:514` |
| Ollama output replaces the text with **no length/language guardrails**, 5 s timeout | `text_postprocess.py:198-209, 548` |
| Recording overlay is Windows-only | README |
| Needs Python 3.11–3.13 (this Mac has 3.14 → `pipx install --python python3.12 whisper-local`) | `README.md` |
| Worth porting: backtracking/stutter rules that never cross a sentence end; per-app rules | `dictation_cleanup.py`, `app_rules.py` |

**Verdict:** fine as a free English dictation tool today; weak for mixed Korean/English on a Mac
(either slow CPU with prompt, or fast Metal without prompt). LocalFlow's niche is exactly that gap.

## 3. Key explanations (for reference)

- **Same model, different runtime.** faster-whisper (CTranslate2), WhisperKit (Core ML) and whisper.cpp
  (GGML) all run OpenAI's Whisper weights. Accuracy is nearly identical; speed depends on whether the
  runtime uses Apple hardware. WhisperKit → Neural Engine; whisper.cpp → Metal; faster-whisper → CPU.
- **CPU does not save memory on Apple Silicon.** CPU, GPU and Neural Engine share one RAM pool. The
  Neural Engine is also the most power-efficient choice for all-day use. → Keep WhisperKit.
- **The real memory cost is the polishing LLM**, not speech-to-text. Most bilingual fixes don't need it:

  | Problem | Fix | LLM? |
  |---|---|---|
  | English words written in Hangul (클로드 코드) | Prompt biasing + replacement dictionary | No |
  | Fillers (음, 어, um, uh), repeated words | Rules | No |
  | Self-correction (3시에, 아니 4시에) | Rules for common patterns | Sometimes |
  | Korean spacing (띄어쓰기), context fillers (그, 이제, 막, like) | LLM | Yes |

## 4. Decisions made → applied to `PLAN.md`

1. **Speech model:** keep WhisperKit `large-v3-turbo` **632 MB** build on the Neural Engine
   (§3 table). faster-whisper ruled out on Mac.
2. **Polishing LLM:** original plan was Qwen3-4B-Instruct 4-bit (~2.5 GB) via MLX Swift.
   Now **start with Qwen3-1.7B 4-bit (~1.2 GB)**; move to 4B only if the eval set says so (§3, Phase 3).
3. **Model lifecycle (new §3.1):** Whisper loads at launch and stays warm (optional idle unload, off
   by default). LLM **starts loading on hotkey down** (hidden behind speaking), unloads after ~5 idle
   min; if not ready in time → rules-only text. Target ~0.5–1 GB at rest, ~2–4 GB peak.
4. **LLM gate (§4.3):** skip the LLM (and don't load it) for < 4 words, clean English-only text, or
   Raw/Light mode. Run it for Korean spacing, context fillers, unresolved self-corrections.
5. **More rules before the LLM (§4.3):** self-correction patterns ("X, no, Y" / "X, 아니 Y"), Hangul →
   English replacement dictionary.
6. **Apple Foundation Models:** optional Phase 3 benchmark candidate only, not the default (user unsure).
7. Hardware table (§8) and risks (§9: LLM cold load after idle) updated to match.

## 5. Where things stand (as of 2026-10-29, from `PLAN.md`)

- **Phase 0 — done (2026-10-19).** 30 real clips recorded. Chosen: turbo 632 MB + language-adaptive
  prompting (en → vocabulary prompt; ko → short mixed sample; replacement dictionary after).
  EN WER 1.3%, KO CER 5.1%, mixed CER 11.7%, ~0.74 s median, ~0.5–0.6 GB. See `bench/results.md`.
- **Phase 1–2 — built, in testing (2026-10-21).** Swift app in `LocalFlow/`: HUD, menu bar panel,
  main window (Home/History/Dictionary/Settings), onboarding, shortcut recorder + hands-free,
  GRDB history, vocabulary + replacements, silence/hallucination filters, password-field fallback.
- **Remaining Phase 2:** `release.sh` + `.dmg`, install test on a second Mac.
- **Next:** Phase 3 (cleanup rules + LLM benchmark with Qwen3-1.7B first, gate, lifecycle).

## 6. Continuing on another Mac

```bash
git clone git@github.com:GioJung97/localflow.git && cd localflow
brew install xcodegen whisperkit-cli ffmpeg whisper-cpp   # whisper-cpp gives whisper-server for bench
# Install Xcode, then: Xcode → Settings → Accounts → Apple ID → Manage Certificates → + Apple Development
scripts/build.sh            # generates LocalFlow.xcodeproj from project.yml, builds, installs to /Applications
```

Not in git (copy manually if you need them):
- `bench/clips/` — your 30 voice recordings (personal; needed to re-run `bench/run.py`).
  Copy via AirDrop/USB to the same path, or re-record with `python3 bench/record.py --device <n>`.
- `bench/results/` raw outputs and `bench/models/` (re-downloaded automatically).
- `rea/` — reference tool clone, not part of the app.
- `LocalFlow.xcodeproj/` — regenerated by `scripts/build.sh` with that Mac's signing team.

Permissions (Microphone, Accessibility, Input Monitoring) must be granted again on each Mac.

### Prompt to start a new session

> Read `CLAUDE.md`, `PLAN.md` and `docs/sessions/`. We're continuing LocalFlow: Phase 2 is built and in
> testing, next is Phase 3 (cleanup). Start by [your task].
