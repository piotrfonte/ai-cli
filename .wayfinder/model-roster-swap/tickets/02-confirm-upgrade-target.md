---
id: W2
title: Confirm the oMLX upgrade target and its architecture support
map: model-roster-swap
labels: [wayfinder:research]
status: closed
assignee: claude
blocked_by: []
---

## Question

What exactly do we upgrade to, and does it register all three architectures?

The current install is a working one. It is git-restorable, but breaking it blind
still costs a rebuild, so this ticket looks before W4 leaps.

### Find out

1. The newest `omlx` on the `jundot/omlx` main branch, and its pinned versions of
   `mlx`, `mlx-lm` and `mlx-vlm`.
2. Whether upstream oMLX registers **`glm4_moe_lite`**, **`qwen3_5`** (as a VLM —
   `Qwen3_5ForConditionalGeneration`) and **Muse Glimmer**. Check
   `omlx/model_discovery.py` and the VLM engine.
3. Whether the KV-cache format version changes. The pinned build writes
   `_CACHE_FORMAT_VERSION "3"`. A change means the existing 15 GB cache is dead
   weight and should be pruned as part of W4.
4. Whether `mtp_enabled` still exists as a per-model setting, and whether upstream
   reads it for `glm4_moe_lite`. Do **not** enable it — this is for the fog entry.
5. Any breaking change to the `omlx serve` flags this repo passes:
   `--paged-ssd-cache-dir`, `--paged-ssd-cache-max-size`, `--hot-cache-max-size`,
   `--memory-guard-gb`, `--max-concurrent-requests`, `--model-dir`.

### Known starting point

Pinned build is `omlx 0.4.2rc1` at `~/.omlx/src` commit `9aa73b19`, with
`mlx_lm 0.31.3` and `mlx_vlm 0.6.1`. Muse Glimmer's mxfp4 sibling was converted with
mlx-vlm **0.6.12**, so mlx-vlm must move at minimum. A previous attempt found Muse
Glimmer support landed roughly 2190 commits after this pin.

### W1 narrows this: only Muse Glimmer needs the upgrade

Two of the three models already serve correctly on the **pinned** build. W1 ran real
completions on it: GLM 4.7 Flash answered through the `batched` engine, and Ternary
Bonsai answered through the `vlm` engine with its vision tower loaded and
`parser=qwen3_coder` tool calling enabled. So `mlx_lm 0.31.3` carries
`glm4_moe_lite`, and `mlx_vlm 0.6.1` carries `qwen3_5`.

This changes the risk balance. The upgrade now serves **one** model, and it puts two
working models at risk. Weigh that in the target, and state what it costs to roll
back if Muse Glimmer still fails to serve after it.

### Deliverable

A short written target: commit or tag to install, the resulting library versions, the
three architectures' support status, and any flag or cache-format change W4 must
handle.

## Resolution

**Target: tag `v0.5.8.dev3` = commit `350dc08b` (2026-08-11), 2190 commits ahead of
the pin.** The upgrade is safe to attempt, it needs no compiler, and it puts far less
at risk than the ticket assumed. All evidence comes from reading the upstream source
at `origin/main` and `v0.5.8.dev3` in `~/.omlx/src`, plus the model configs on disk.

### 1. The target, and why the tag and not the tip

| | Pinned now | Target `v0.5.8.dev3` |
|---|---|---|
| commit | `9aa73b19` (2026-06-08) | `350dc08b` (2026-08-11) |
| `omlx` | 0.4.2rc1 | 0.5.8.dev3 |
| `mlx` | 0.31.2 (pin reads `>=0.31.2`) | **`==0.32.0`** (exact) |
| `mlx-metal` | 0.31.2 | moves with `mlx` |
| `mlx-lm` | git `bdb77dae` (0.31.3) | git **`ab1806e8`** (also 0.31.3) |
| `mlx-vlm` | git `526c210b` (0.6.1) | git **`78b96eb5`** |
| `transformers` | 5.10.2 (pin reads `>=5.0.0`) | **`>=5.12.1,<5.13`** |

`origin/main` is exactly **one commit** past the tag: `2450a53c`, "add web search tools
to chat". Its only dependency effect is to add `ddgs==9.14.1` (which drags in
click/primp/lxml) for a chat feature this repo does not use. So the tag is the same
serving code, one package leaner, and a named pin. **Take the tag.**

New runtime dependencies that arrive with the target, none optional:
`dflash-mlx` (jundot fork `884b5dc7`), `cohere_melody`, `openai-harmony`,
`markitdown[pdf,docx,pptx]`, `socksio`, `tabulate`, `mistral-common>=1.10`,
`huggingface-hub>=1.19.0`.

### 2. Architecture support — only Muse Glimmer needs the upgrade, and it is present

Read from each `config.json` on disk, then matched against
`omlx/model_discovery.py` at both refs:

| Model | `model_type` | `architectures` | Pinned | Target | Engine |
|---|---|---|---|---|---|
| GLM 4.7 Flash | `glm4_moe_lite` | `Glm4MoeLiteForCausalLM` | serves (W1) | serves | `batched` (mlx-lm) |
| Bonsai 27B | `qwen3_5` | `Qwen3_5ForConditionalGeneration` | serves (W1) | serves | `vlm` |
| Muse Glimmer | `muse_glimmer` | `MuseGlimmerForConditionalGeneration` | **absent** | **registered** | `vlm` |

- **Muse Glimmer** is registered twice at the target and neither entry exists at the
  pin: `muse_glimmer` in `VLM_MODEL_TYPES`, and
  `MuseGlimmerForConditionalGeneration` in the architecture list.
- **Bonsai's `qwen3_5` is in neither list, at either ref.** It reaches the VLM engine
  through `detect_model_type()`'s catch-all, which routes on the presence of
  `vision_config` — "Catch-all for VLMs that aren't yet listed in VLM_MODEL_TYPES".
  Bonsai has one. The route is unchanged by the upgrade, so W1's result carries.
- **GLM is not a VLM**, so it goes to `BatchedEngine` and mlx-lm handles it. mlx-lm
  moves from commit `bdb77dae` to `ab1806e8` — both labelled 0.31.3 — and the target's
  own comment names a "DeepSeek/GLM DSA indexer RoPE fix" among the changes.

**The upgrade is not the only way to get Muse Glimmer, but it is the only safe way.**
oMLX does not wait for mlx-vlm to ship the model: it **vendors** it at
`omlx/patches/mlx_vlm_muse_glimmer_compat/`, from mlx-vlm PR #1838 plus the
quantization fix from PR #1839, "both newer than oMLX's mlx-vlm pin (`78b96eb`)". The
patch installs onto the real `mlx_vlm.models` namespace and is applied automatically
at load (`utils/model_loading.py`: `if for_vlm and model_type == "muse_glimmer"`).

That kills the map's worry that mlx-vlm must reach 0.6.12 — it must not. It also
raises a sharper hazard, stated in the vendor README: **without PR #1839's
`QuantizedNormedEmbedding`, quantizing `embed_tokens` silently drops the weightless
`embed_norm` and logits collapse.** Our model is a 4-bit affine quant, so it is
exactly the case that fix protects. Bumping mlx-vlm alone, or vendoring by hand,
would produce a model that loads and answers nonsense. Take oMLX whole.

`dflash-mlx` is **not** required to serve Muse Glimmer. It carries drafter support for
speculative decode, which stays off.

### 3. KV cache format — unchanged, no prune forced

`_CACHE_FORMAT_VERSION` is `"3"` at both refs. The target's
`_READABLE_CACHE_FORMAT_VERSIONS` widens to `{"2","3","5", POOLING_CACHE_DELTA…}`, so
the 15 GB already in `~/.omlx/cache` stays readable. **W4 does not have to prune for
correctness.** It should still prune for space — see §6.

### 4. `mtp_enabled` survives, but GLM 4.7 Flash can never use it

`mtp_enabled` is still a per-model field of `ModelSettings` at the target, alongside
`vlm_mtp_enabled`, `vlm_mtp_draft_model` and a new `dflash_*` family. So
`patch-omlx-mtp.mjs` keeps working.

**But MTP on GLM 4.7 Flash is dead three times over.** This settles the fog entry
rather than leaving it open:

1. **The gate excludes it.** `_is_mtp_compatible()` admits `qwen3_5*`, `qwen3_6*`,
   `deepseek_v4*`, `nemotron_h*`, `glm_moe_dsa`, `gemma4`, `inkling*` and `step3p7`.
   `glm4_moe_lite` is not there.
2. **The GLM MTP patch is a different model.** `patches/mlx_lm_mtp/glm_moe_dsa_model.py`
   is logged as the "GLM-5.2 MTP patch" and imports `patches/glm_moe_dsa/deepseek_v32`.
   `glm4_moe_lite` appears **once** in the whole upstream tree, in an unrelated
   `scheduler.py` comment.
3. **The weights are not in the checkpoint.** `config.json` declares
   `num_nextn_predict_layers: 1`, but the 6-bit conversion has **0 of 1970 tensors**
   matching `mtp`/`nextn`. The quantizer dropped the head.

A related risk is therefore also absent. The target applies the MTP patch even when
`mtp_enabled` is false, for *sanitize correctness* — stock mlx-lm shifts norms by +1
when it sees `mtp.*` keys, which double-shifts an already-converted MLX checkpoint into
garbage tokens. With no `mtp.*` keys in our GLM build, there is nothing to shift.

### 5. `omlx serve` flags — all six survive

`--model-dir`, `--max-concurrent-requests`, `--memory-guard-gb`,
`--paged-ssd-cache-dir`, `--paged-ssd-cache-max-size` and `--hot-cache-max-size` are
all still declared in `omlx/cli.py` at the target. No flag change for `ai.sh`.

`EnginePool.resolve_model_id()` still strips the provider prefix at the first `/` and
re-matches against the directory-leaf entry, so W1's **leaf-keying rule holds** and
`patch-omlx-mtp.mjs` must keep writing both spellings.

### 6. What W4 must handle — three practical traps

**a. No compiler is needed, and W4 must keep it that way.** The target's
`[build-system]` adds `cmake>=3.27`, `nanobind==2.13.0` and `mlx==0.32.0`. That reads
like a blocker, because **cmake is not installed on this box**. It is not: `setup.py`
only adds `ext_modules` when `OMLX_WITH_CUSTOM_KERNEL=1` or `--with-custom-kernel` is
passed. A plain install compiles nothing. **Do not set that variable.**

Two custom kernels exist that we therefore will not have:
`omlx.custom_kernels.bonsai._ext` and `omlx.custom_kernels.glm_moe_dsa._ext`. The
first is named for our `--bonsai` model. Building it needs `brew install cmake` and an
exact nanobind/mlx ABI pair. That is a measurable-later question, not a first-cut one
— it belongs in the fog.

PEP 517 build isolation still installs the `requires` list into a throwaway env, so
the install downloads cmake, nanobind and a second `mlx` wheel even though nothing
compiles. `--no-build-isolation` would avoid it but the venv has **no setuptools, no
wheel and no pip**, so isolation is the practical path. Budget the transient.

**b. Rollback is only partial if done naively.** The pinned `pyproject.toml` uses
*floors*, not exact pins: `mlx>=0.31.2` and `transformers>=5.0.0`. Reinstalling the old
checkout therefore leaves `mlx 0.32.0` and `transformers 5.12.x` in place, because both
satisfy the floor. The git-pinned `mlx-lm`/`mlx-vlm` do revert. The full recipe is:

```bash
git -C ~/.omlx/src checkout 9aa73b19
VIRTUAL_ENV=~/.omlx/venv uv pip install -e ~/.omlx/src \
  "mlx==0.31.2" "mlx-metal==0.31.2" "transformers==5.10.2"
```

Rollback state to restore: `omlx 0.4.2rc1`, `mlx 0.31.2`, `mlx-metal 0.31.2`,
`mlx-lm 0.31.3` (`bdb77dae`), `mlx-vlm 0.6.1` (`526c210b`), `transformers 5.10.2`,
Python 3.12.13, checkout `9aa73b19` clean.

**c. Disk is now the binding constraint, worse again than W1 measured.**
**13 GiB free, 99% full** on `/System/Volumes/Data` — down from W1's 35 GB, because
Muse Glimmer's 18 GB finished landing. The venv is 969 MB today and the upgrade adds
a large dependency set. `~/.omlx/cache` holds 15 GB against a budget W8 cuts to 25 GB.
Pruning that cache before the upgrade is the cheap fix: blocks are content-addressed,
so a pruned block is a cache miss and a recompute — the safe failure mode — and §3
shows no format reason to keep them.

### 7. Risk balance, as the ticket asked

The upgrade serves **one** model and risks two. That framing survives contact, but
both halves are smaller than feared:

- **What it buys.** Muse Glimmer, which the pin cannot load at all, and which cannot
  be back-ported safely because of the #1839 quantization fix.
- **What it risks.** GLM changes mlx-lm commit inside one version, and Bonsai's VLM
  route is a `vision_config` catch-all that is identical at both refs. Neither is
  untouched, so W5 and W6 still have to run — but neither depends on a code path the
  upgrade rewrites.
- **What rollback costs.** One `git checkout` and one `uv pip install` with three
  explicit pins, per §6b. The weights are untouched by any of this, and the KV cache
  survives per §3.

### Deferred to the fog, deliberately

- Building the `bonsai` and `glm_moe_dsa` custom kernels (needs cmake; unmeasured).
- `dflash` speculative decode, now a first-class oMLX feature with its own settings
  family and Muse Glimmer drafter support.
- MTP for GLM 4.7 Flash — this ticket closes it instead: impossible with this
  checkpoint.
