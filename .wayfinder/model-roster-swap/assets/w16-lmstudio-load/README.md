# W16 — which roster models load in LM Studio

Method and raw results for
[Verify which roster models actually load in LM Studio](../../tickets/16-lmstudio-load-check.md).

## The box was not in the expected state

LM Studio's **application was missing** when this ticket started. The `lms` CLI, its
1.1 GB of runtimes and all of its data survived, but no `LM Studio.app` existed
anywhere, and every CLI command failed with:

```
Error: LM Studio daemon is not running and no valid installation could be found or installed.
```

An empty `staged-updates-app` directory plus an `lms` binary rewritten at 13:25 on the
same day point at a **failed self-update**, not a deliberate uninstall.

**Before reinstalling**, LM Studio's own `model-data.json` was read. It records
`lastAttemptedToLoadTimestamp` and `lastLoadedTimestamp` per model key:

| Key | Attempted | Loaded OK |
|---|---|---|
| `zai-org/glm-4.7-flash` | 2026-08-11 09:33:36 | 09:33:48 |
| `prism-ml/bonsai-27b` | 2026-08-12 00:44:29 | 00:44:39 |
| `mlx-community/Muse-Glimmer-30B-4bit` | 2026-08-12 13:25:42 | never |

The Muse row matches [W10](../../tickets/10-remove-muse-gguf.md) exactly, which is what
proves the field means *successful load* rather than *attempt*. This archive is kept
because it is independent of everything done afterwards.

## Setup

- **Reinstalled** `brew install --cask lm-studio` → **0.4.21+2**, with the user's
  approval.
- **The runtime did not change**: `mlx-llm-mac-arm64-apple-metal-advsimd 1.11.0`
  carrying `mlx_lm 0.31.3`, `mlx_vlm 0.6.5`, `mlx 0.32.0` — the same versions W10
  measured, so W10's Muse Glimmer verdict still stands on the runtime it was made on.
  `mlx_lm` carries `glm4_moe_lite.py`; `mlx_vlm` carries `bonsai` and `qwen3_5`; neither
  carries `muse_glimmer`.
- **The fresh app did not index the model store.** `settings.json` still held
  `downloadsFolder: /Users/p/.cache/huggingface/hub`, but `lms ls` reported only the
  app's own bundled embedding model, and a load by key returned `Model not found`.
  Waiting, focusing the window and completing startup changed nothing.
- **Fix applied**: the two roster directories were symlinked into LM Studio's default
  folder — one inode each, no copy, no disk cost:

  ```
  ~/.lmstudio/models/lmstudio-community/GLM-4.7-Flash-MLX-6bit
      -> ~/.cache/huggingface/hub/lmstudio-community/GLM-4.7-Flash-MLX-6bit
  ~/.lmstudio/models/prism-ml/Ternary-Bonsai-27B-mlx-2bit
      -> ~/.cache/huggingface/hub/prism-ml/Ternary-Bonsai-27B-mlx-2bit
  ```

  LM Studio indexed both in **5 s**, under the **same hub keys** and with **byte-identical
  sizes** to W10's listing (8.52 GB / 24.36 GB), so the keys this ticket records are the
  real ones and not an artefact of the workaround.
- oMLX stayed down throughout. One model at a time, `-c 16384`, `--ttl 900`.

## The gate

`gate.py` applies the map's standard serve gate (constraint 9, as sharpened by W1, W6
and W14) to LM Studio's OpenAI-compatible endpoint on port 1234:

- `finish_reason` must be `stop`
- `content` must be non-empty
- `max_tokens` is **8192** — W14's working figure; 4096 is the floor

```bash
python3 gate.py zai-org/glm-4.7-flash results-glm.json
python3 gate.py prism-ml/bonsai-27b   results-bonsai.json
```

Prompt (same for both, recorded so the run is reproducible):

> Write a Python function that reverses a singly linked list in place. The node class is
> `class Node: __init__(self, val, next=None)`. Return only the function.

## Verdict

| Model | LM Studio key | oMLX id | Loads? | Gate at defaults? |
|---|---|---|---|---|
| GLM 4.7 Flash 6-bit | `zai-org/glm-4.7-flash` | `lmstudio-community/GLM-4.7-Flash-MLX-6bit` | **yes** — 16.27 s, 22.68 GiB | **no** — `finish_reason: length` |
| Ternary Bonsai 27B 2-bit | `prism-ml/bonsai-27b` | `prism-ml/Ternary-Bonsai-27B-mlx-2bit` | **yes** — 8.77 s, 7.94 GiB | **yes** — `finish_reason: stop` |
| Muse Glimmer 30B 4-bit | — | `mlx-community/Muse-Glimmer-30B-4bit` | **no** (W10, runtime unchanged) | — |

## Why GLM fails the gate, exactly

GLM answered the question **correctly and immediately**, then emitted `<|user|>` and
carried on generating a fabricated dialogue until it hit the 8192-token cap:

```
```python
def reverse_list(head): ...
```<|user|>
The node class is `class Node: ...`. Write a Python function that reverses a singly ...
```

The cause is a **stop-token gap in LM Studio, not a defect in the model**:

| Source | Value |
|---|---|
| `config.json` → `eos_token_id` | `[154820, 154827, 154829]` |
| resolved via `tokenizer.json` | `<\|endoftext\|>`, `<\|user\|>`, `<\|observation\|>` |
| `tokenizer_config.json` → `eos_token` | `<\|endoftext\|>` **only** |

LM Studio honours the single `eos_token` and ignores the other two ids. GLM ends its
turns with `<|user|>` (154827), so generation never stops. oMLX honours the full list,
which is why [W5](../../tickets/05-serve-check-glm.md) passed the same weights.

The control run proves it — same prompt, same load, one added parameter:

| Run | `stop` | finish_reason | completion tokens | content | elapsed |
|---|---|---|---|---|---|
| `results-glm.json` | none | **length** | 8191 | 30,789 chars | 291.89 s |
| `results-glm-withstop.json` | `["<\|user\|>","<\|endoftext\|>"]` | **stop** | 509 | 221 chars, correct | 14.02 s |

So GLM is declarable under the `lmstudio` provider **only if the caller supplies the
stop strings**. Declared bare, every turn runs to the token cap.

## Out of scope, recorded as an observation only

Decode rate in LM Studio was **28.1 tok/s** (GLM) and **16.1 tok/s** (Bonsai), against
oMLX's 68 and 38 from W5 and W6. These are single short-prompt samples at each runtime's
default settings, with no attempt to match load parameters — **not** a cross-runtime
benchmark, and not evidence for one. W16 checks honesty of declaration, nothing more.

## State left behind

- LM Studio 0.4.21 installed, **server stopped**, no model loaded, app quit — matching
  how the box was found, except that the app now exists again.
- **The two symlinks were kept.** They cost no disk, and without them LM Studio indexes
  zero LLMs, which is worse than the state this ticket found. Remove with:

  ```bash
  rm ~/.lmstudio/models/lmstudio-community/GLM-4.7-Flash-MLX-6bit \
     ~/.lmstudio/models/prism-ml/Ternary-Bonsai-27B-mlx-2bit
  ```

## Files

| File | What |
|---|---|
| `gate.py` | the gate, aimed at LM Studio's port 1234 |
| `results-glm.json` | GLM at LM Studio defaults — FAIL |
| `results-glm-withstop.json` | GLM with explicit stop strings — PASS |
| `results-bonsai.json` | Bonsai at LM Studio defaults — PASS |
