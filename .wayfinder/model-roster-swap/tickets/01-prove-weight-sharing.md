---
id: W1
title: Prove weight sharing between LM Studio and oMLX
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: []
---

## Question

Can oMLX and LM Studio serve the **same bytes on disk**, and what is the mechanism?
Sharing is a blocker for this map, so this ticket gates almost everything else.

This is provable **today**, with no download and no upgrade: GLM 4.7 Flash 6-bit and
Bonsai 27B are already in LM Studio's store.

### What is already known

- LM Studio's model store **is** `~/.cache/huggingface/hub`, but it writes flat
  `<publisher>/<repo>/` directories — *not* HF's `models--org--repo/snapshots/<sha>/`.
- Every standard `models--*` snapshot has been deleted from that cache, which is why
  all four `~/.omlx/models/*` symlinks currently dangle.
- LM Studio's flat layout happens to match oMLX's two-level model ids exactly.
- oMLX discovers models from the subdirectories of `--model-dir`, and keys per-model
  settings by the **directory leaf**, not the two-level id.

### Decided while charting

- The store is LM Studio's. oMLX reaches it by symlink from
  `~/.omlx/models/<org>/<repo>` — **not** by repointing `OMLX_MODEL_DIR`, which would
  strand `bge-m3` and expose LM Studio's GGUF files to oMLX discovery.

### Acceptance gate (all three parts)

1. Exactly one copy of the weights exists on disk.
2. oMLX serves the model through `~/.omlx/models/<org>/<repo>`.
3. `lms ls` still lists the model **after** the symlink exists.

Part 3 is the one that catches real regressions — a symlink or a permission change
inside LM Studio's own store is how sharing breaks in practice.

### Deliverable

The symlink layout, proven on GLM and Bonsai, written up precisely enough that
ticket W8 can implement `_ensure_model` against it. Also record what the served oMLX
id and directory leaf are for each model, since `opencode.json` and
`model_settings.json` key off them differently.

## Resolution

**Sharing works.** A directory symlink is the mechanism. The gate passes on all
three parts, on the current pinned oMLX (0.4.2rc1), with no upgrade and no download.

### The layout

```bash
ln -sfn ~/.cache/huggingface/hub/lmstudio-community/GLM-4.7-Flash-MLX-6bit \
        ~/.omlx/models/lmstudio-community/GLM-4.7-Flash-MLX-6bit
ln -sfn ~/.cache/huggingface/hub/prism-ml/Ternary-Bonsai-27B-mlx-2bit \
        ~/.omlx/models/prism-ml/Ternary-Bonsai-27B-mlx-2bit
```

Both links are in place now.

### The gate

1. **One copy.** The same inode answers through both paths — 118233930 for GLM
   shard 1, 118235385 for the Bonsai tensor file. A sweep of `~/.omlx`,
   `~/.lmstudio` and `~/Library/Caches` finds no other `*.safetensors` above 1 GB,
   except `bge-m3`.
2. **oMLX serves through the link.** The server log shows
   `BatchedEngine loaded: /Users/p/.omlx/models/lmstudio-community/GLM-4.7-Flash-MLX-6bit`
   and
   `VLMBatchedEngine loaded: /Users/p/.omlx/models/prism-ml/Ternary-Bonsai-27B-mlx-2bit`.
   Both models answered `SHARING OK` with `finish_reason: stop`.
3. **LM Studio is not disturbed.** `lms ls` gives byte-identical output before and
   after the links exist — 3 models, 32.96 GB. A stronger check also passes: LM
   Studio loaded Bonsai from the same bytes (7.94 GiB in 6.96 s) and answered
   `SHARING OK` through port 1234.

### Ids, for W8 and W9

The served id is the **directory leaf**. `resolve_model_id()` removes everything
before the first `/`, so the two-level id that `opencode.json` sends resolves to the
same model.

| Profile | Id sent by opencode | Served id and `model_settings.json` leaf key |
|---|---|---|
| bare `ai` | `mlx/lmstudio-community/GLM-4.7-Flash-MLX-6bit` | `GLM-4.7-Flash-MLX-6bit` |
| `--muse` | `mlx/mlx-community/Muse-Glimmer-30B-4bit` | `Muse-Glimmer-30B-4bit` |
| `--bonsai` | `mlx/prism-ml/Ternary-Bonsai-27B-mlx-2bit` | `Ternary-Bonsai-27B-mlx-2bit` |

`patch-omlx-mtp.mjs` must keep writing **both** spellings, as CLAUDE.md records.

### Discovery facts W8 must know

- **oMLX already scans the HF cache by itself.** `~/.omlx/settings.json` carries
  `huggingface.hf_cache_enabled: true`, and `get_effective_model_dirs()` appends
  `~/.cache/huggingface/hub` after `--model-dir`. All three models appear even with
  no symlink; Muse Glimmer appeared this way, mid-download.
  - So the symlink is not what makes a model visible. It makes `--model-dir`
    **authoritative**: discovery reads `--model-dir` first, so the symlinked copy
    wins the duplicate tie-break. oMLX logs a benign `Duplicate model_id` warning.
  - Keep the symlinks. They are explicit, they give `_ensure_model` a path to
    verify, and they survive `hf_cache_enabled: false`.
  - GGUF exposure is **not** a risk here. `_is_hf_cache_mlx_compatible()` demands a
    `model*.safetensors` file, so a GGUF in that cache is skipped.
- **Dangling symlinks are skipped in silence.** The five old links (Macaw, both Qwen
  quants, the Jundot build, Gemma) caused no error and no log line. Their removal is
  tidiness, not correctness.

### The shape `_ensure_model` needs

For the selected profile only:

1. Read `~/.cache/huggingface/hub/<org>/<repo>`.
2. If the directory holds no `*.safetensors`, **fail loudly by name**. No download.
3. If it holds a `downloading_*.part` file, fail the same way — LM Studio is still
   fetching. This state is live on Muse Glimmer right now.
4. Else `mkdir -p ~/.omlx/models/<org>` and `ln -sfn`. This is idempotent.

### A trap this ticket found — W5, W6 and W7 must not step in it

Notes constraint 9 asks for a non-empty `content` assertion. That alone is **not
enough**. Both models put the answer in `content` and the thinking in
`reasoning_content`, but only after the reasoning block closes. Cut the generation
short and the whole reasoning comes back inline in `content`, with no
`reasoning_content` key at all — which passes a non-empty test while answering
nothing.

| Model | `max_tokens` | `finish_reason` | `content` | `reasoning_content` |
|---|---|---|---|---|
| GLM | 200 | `length` | 863 chars of thinking | absent |
| GLM | 1024 | `stop` | `SHARING OK` | 1122 chars (252 tokens used) |
| Bonsai | 64 | `length` | 233 chars of thinking | absent |
| Bonsai | 200 | `stop` | `SHARING OK` | 585 chars |

**Every serve check must assert `finish_reason: stop` **and** non-empty `content`,
with `max_tokens` at 1024 or above.**

### Numbers seen in passing

These are not the measurement — W5 and W6 own that.

- GLM: cold load 5.46–5.75 s, 22.89 GB resident.
- Bonsai: load 1.65–3.38 s, 8.59 GB resident; the vision tower loads and does not
  block text serving. oMLX reports `VLM tool calling enabled: parser=qwen3_coder`.
- Both models resident together: 32.10 GB, under the 48 GB guard.

### Facts other tickets depend on

- **Disk is worse than the map states.** 35 GB free at 97% full, not 59 GB at 94%.
  Muse Glimmer holds 14 GB of its download so far.
- **The Muse GGUF is already an orphan.** `lms ls` reports 3 models and does not
  list `~/.lmstudio/models/lmstudio-community/Muse-Glimmer-30B-GGUF` (17 GB). LM
  Studio's store is now the HF cache, so that tree is unindexed dead weight. This
  strengthens W10.
- **W3 is not done.** Shard 3 of 4 is still `downloading_...part`.
- `~/.omlx/settings.json` holds `cache.ssd_cache_dir: ~/.omlx/cache-next`, an empty
  directory, while `~/.omlx/cache` holds 15 GB. The CLI flag overrides it, so
  `ai.sh` is safe. The persisted setting disagrees with the launcher.
