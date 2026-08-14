---
id: W16
title: Verify which roster models actually load in LM Studio
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: []
---

## Question

**Which roster models can the `lmstudio` provider honestly declare?**

Constraint 10 of the map keeps the `lmstudio` provider block "rewritten to declare all
three models, so the same model can be A/B'd across both runtimes".
[W10](10-remove-muse-gguf.md) proved that is not achievable for one of them, and cast
doubt on the assumption behind the other two.

### What W10 established

`lms load muse-glimmer-30b` **fails**:

```
ValueError: Model type muse_glimmer not supported.
Error: No module named 'mlx_vlm.speculative.drafters.muse_glimmer'
```

LM Studio's MLX runtime is `mlx-llm-mac-arm64-apple-metal-advsimd@1.11.0`, carrying
**mlx_vlm 0.6.5**. Upstream needs **0.6.12** for Muse Glimmer ([W2](02-confirm-upgrade-target.md)),
and oMLX only serves it by **vendoring** the implementation. `lms runtime update` reports
everything already up to date, so nothing available closes this today.

**The trap this ticket exists to avoid:** LM Studio *indexed* Muse Glimmer perfectly —
`lms ls` listed it with the right arch, the right size and the right path — and still
could not load it. **Indexing does not predict loading.** So the fact that `bonsai` and
`glm_moe_dsa` both appear in mlx_vlm 0.6.5's `models/` directory is encouraging, not
sufficient.

### What to do

For **GLM 4.7 Flash** (`zai-org/glm-4.7-flash`, 24.36 GB) and **Bonsai**
(`prism-ml/bonsai-27b`, 8.52 GB), and for each one only:

1. `lms load <key> -y --ttl 600` — does it instantiate at all?
2. If it loads, send one real chat request through LM Studio's server and apply the
   map's standard gate: **`finish_reason: stop`, non-empty `content`, `max_tokens` at
   4096 or above** (constraint 9 — a short cap has already fooled this map twice).
3. `lms unload` afterwards. Leave LM Studio as you found it, including whether its
   server was running.

**Run oMLX down** (`ai -k`) so a 24 GB load does not fight the memory guard, and load one
model at a time.

### What the answer must record

A three-row verdict table — model, loads?, answers the gate? — because that table *is*
the `lmstudio` provider block W9 writes. Muse Glimmer's row is already filled in: **no**.

Record the exact model keys too. They are not the `mlx` provider's ids: LM Studio uses
`zai-org/glm-4.7-flash` and `prism-ml/bonsai-27b`, while oMLX serves the directory leaf.
W9 needs both spellings.

### Scope

This checks that a declaration is **honest**. It is not a capability comparison and not a
cross-runtime benchmark — [W14](14-capability-comparison.md) owns capability. If a model
loads and answers, its row is done; do not measure it further here.

## Resolution

**The `lmstudio` provider can declare one model honestly, not two — and the box was not
in the state this ticket assumed.** LM Studio's **application was gone**. Only the CLI,
its runtimes and its data survived, so the ticket started with a reinstall.

Method, raw results and the full setup: [assets/w16-lmstudio-load](../assets/w16-lmstudio-load/).

### 1. The verdict table

| Model | LM Studio key | oMLX id | Loads? | Answers the gate? |
|---|---|---|---|---|
| GLM 4.7 Flash 6-bit | `zai-org/glm-4.7-flash` | `lmstudio-community/GLM-4.7-Flash-MLX-6bit` | **yes** — 16.27 s, 22.68 GiB | **no** — `finish_reason: length` |
| Ternary Bonsai 27B 2-bit | `prism-ml/bonsai-27b` | `prism-ml/Ternary-Bonsai-27B-mlx-2bit` | **yes** — 8.77 s, 7.94 GiB | **yes** — `finish_reason: stop` |
| Muse Glimmer 30B 4-bit | — | `mlx-community/Muse-Glimmer-30B-4bit` | **no** (W10) | — |

Both key spellings are recorded, as W9 requires. The LM Studio keys are the **hub**
keys, not the directory ids, and they are confirmed live rather than copied from W10.

### 2. GLM loads and still cannot be declared bare

GLM answers the question **correctly and at once**, then emits `<|user|>` and generates
a fabricated dialogue until it reaches the 8192-token cap — 30,789 characters in 291.89 s.

The cause is a **stop-token gap in LM Studio, not a defect in the model**. `config.json`
declares `eos_token_id: [154820, 154827, 154829]`, which `tokenizer.json` resolves to
`<|endoftext|>`, `<|user|>` and `<|observation|>`. But `tokenizer_config.json` names only
`<|endoftext|>` as `eos_token`, and LM Studio honours that one alone. GLM ends its turns
with `<|user|>` (154827), so nothing stops it. oMLX honours the whole list, which is why
[W5](05-serve-check-glm.md) passed these same weights.

One added parameter proves it, on the same load:

| Run | `stop` | finish_reason | completion tokens | elapsed |
|---|---|---|---|---|
| defaults | none | **length** | 8191 | 291.89 s |
| control | `["<\|user\|>","<\|endoftext\|>"]` | **stop** | 509 | 14.02 s |

So GLM is declarable **only if the caller supplies the stop strings**. Declared bare,
every turn runs to the token cap.

**This is the second time GLM's runaway has been measured.** [W14](14-capability-comparison.md)
found it wasted 4 of 12 turns on `finish_reason: length` under oMLX. The mechanism here is
a different one — a runtime stop-token gap, not the model — but it lands on the same model,
and W18 should not read the two as one fault.

### 3. What the reinstall did and did not change

- **The runtime is unchanged**: `mlx-llm 1.11.0` with `mlx_lm 0.31.3`, `mlx_vlm 0.6.5`,
  `mlx 0.32.0` — the versions W10 measured. So **W10's Muse Glimmer verdict still holds**
  on the runtime it was made on, and Muse was not re-tested. `mlx_vlm 0.6.5` still has no
  `muse_glimmer` module; it does carry `bonsai` and `qwen3_5`, and `mlx_lm` carries
  `glm4_moe_lite.py`.
- **The fresh app does not index the configured store.** `settings.json` still holds
  `downloadsFolder: ~/.cache/huggingface/hub`, yet `lms ls` listed only the app's bundled
  embedding model and a load by key returned `Model not found`. Symlinking the two model
  directories into `~/.lmstudio/models/<org>/<repo>` fixed it in 5 s — one inode each, no
  copy — and produced the **same hub keys and byte-identical sizes** as W10, so the
  workaround does not distort the recorded keys. The links are kept, because without them
  LM Studio sees zero LLMs.

### 4. Evidence that survived the missing app

Before the reinstall, LM Studio's `model-data.json` already recorded the answer to
"does it load", and it agrees with the live result exactly:

| Key | Attempted | Loaded OK |
|---|---|---|
| `zai-org/glm-4.7-flash` | 2026-08-11 09:33:36 | 09:33:48 |
| `prism-ml/bonsai-27b` | 2026-08-12 00:44:29 | 00:44:39 |
| `mlx-community/Muse-Glimmer-30B-4bit` | 2026-08-12 13:25:42 | **never** |

The Muse row matches W10, which is what proves the field means a *successful* load. The
live test was still needed: the archive answers step 1 and says nothing about the gate —
and the gate is exactly where GLM failed.

### 5. What W9 must do with this

- Declare **`prism-ml/bonsai-27b`** under the `lmstudio` provider without qualification.
- Declare **`zai-org/glm-4.7-flash`** only **with** `stop: ["<|user|>", "<|observation|>"]`
  carried in its config. Without that the declaration is dishonest by this ticket's own
  standard, and W9 should leave the model out rather than ship a runaway.
- Leave **Muse Glimmer out**. The block declares fewer than three, as W10 predicted.
- Note that `opencode.json` sets `"temperature": false` for the `mlx` entries so oMLX
  falls back to each model's `generation_config.json`. A stop-string list is a different
  kind of setting — it is a correctness requirement here, not a preference.

### 6. Out of scope, recorded as an observation only

Decode ran at **28.1 tok/s** (GLM) and **16.1 tok/s** (Bonsai) in LM Studio, against
oMLX's 68 and 38. These are single short-prompt samples at each runtime's defaults, with
no attempt to match load parameters. They are **not** a cross-runtime benchmark and must
not be quoted as one.

### 7. State left behind

LM Studio 0.4.21+2 installed, server stopped, nothing loaded, app quit. oMLX stayed down
throughout. Free disk fell from 25.7 GB to 20 GiB, mostly the app itself.
