---
id: W7
title: Serve-check Muse Glimmer 30B 4-bit and measure it
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: [W1, W3, W4]
---

## Question

Does `mlx-community/Muse-Glimmer-30B-4bit` serve real coding turns on oMLX, and is it
usable this time? This becomes `--muse`.

### The history this ticket exists to settle

`Jundot/Muse-Glimmer-30B-oQ4e` was removed on 2026-08-10 for prefill of ~200 tok/s —
~64 s before the first token on a 12.8k-token agentic turn, and 1m 16s for one real
turn. Decode was never the problem; it passed the ≥15 tok/s gate throughout.

That measurement belongs to a **different artifact**: an oMLX-native oQ4e quant on
`omlx 0.5.8.dev3`. This is a flat 4-bit mlx-community conversion on the newly
upgraded build. Treat it as unmeasured — and measure it.

A flat 4-bit quant does not fix prefill, which is compute-bound. If the number comes
back the same, that is a finding, not a failure of this ticket.

### Measure

Same protocol as W5. Prefill directly with `max_tokens: 1` at ~10k and ~25k — this is
the headline number for this model. Then decode, resident memory, cold load. Assert
**non-empty `content`** and `finish_reason: stop`; confirm tool calling end to end.

### The gate

Report **time to first token on a ~12.8k-token prompt** explicitly, because that is
the number that killed the last attempt and the only one comparable to it.

### Watch for

- It is a dense 30B VLM with a perception encoder. Confirm resident memory with the
  encoder loaded, and that `--muse` fits beside the 8 GB hot cache under the 40.8 GB
  soft threshold.
- The previous Muse profile needed **reasoning capped to medium** (commit `6f6c030`).
  Settings stay at defaults per the charting decision, but if the model runs away in
  `reasoning_content`, that history is the first thing to try.
- The previous profile also ran **without opencode-mem**, because a dense 30B
  summarizer held a concurrent slot for minutes. Note whether that pressure returns.

### Gate correction from W1

`max_tokens` must be **1024 or above**. W1 measured that a short cap returns the whole
reasoning inline in `content` with **no `reasoning_content` key**, so the pair
(non-empty `content`, `finish_reason: stop`) only holds when the reasoning block gets
room to close. GLM needed 252 tokens for a one-line answer.

### From W2 and W3 — serve it on the upgraded oMLX as a whole, never a partial bump

W3 confirms the weights: 19.41 GB, 4 shards matching the index exactly, flat **4-bit
affine** (group size 64), 2278 tensors of which 815 are vision. `model_type` is
`muse_glimmer`; the served id and settings leaf key are `Muse-Glimmer-30B-4bit`.

**The load-correctness hazard lands squarely on this model.** oMLX does not get Muse
Glimmer from mlx-vlm — it **vendors** the implementation from mlx-vlm PR #1838 plus
the quantization fix from PR #1839. Without #1839's `QuantizedNormedEmbedding`,
quantizing `embed_tokens` silently drops the weightless `embed_norm` and logits
collapse. This is a quantized checkpoint, so that fix is load-bearing. If this ticket
ever gets tempted to "just bump mlx-vlm" instead of taking the oMLX upgrade whole, the
result will load, answer, and be wrong.

`dflash-mlx` installs with the upgrade and carries a Muse Glimmer drafter. Leave it
off — same reasoning as MTP.

**KV is not the risk.** 52 layers × 2 KV heads × head_dim 128 ⇒ ~52 KB/token, about
**3.4 GB at 65 k**, close to GLM's. Prefill and the dense 30B forward pass are what
this ticket measures.

**Read the estimator line too — added by W5.** W5 found oMLX sizing GLM's KV **7×**
too high, so its prefill memory guard rejected a 65k prompt in 5.1 s with the model
alone in memory. This model's KV shape is conventional, so the uniform formula should
be right here — but record oMLX's `Model info set: … Estimated memory per 64-token
block: X MB` line at load and check `X` against the ~52 KB/token above. A dense 30B
plus a vision tower leaves the least headroom of the three, so a wrong estimate hurts
most here. The number feeds
[Decide GLM's context cap against oMLX's 7x MLA over-count](12-glm-context-cap.md).

W5 also found the **first** large prefill after a model load runs at about half the
steady cold rate. Discard the first run of each size, or this ticket will convict
Muse Glimmer on a warm-up number — exactly the ~200 tok/s history it exists to settle.

**The oMLX symlink does not exist yet** — W8 owns it. This ticket does not need it:
oMLX scans `~/.cache/huggingface/hub` on its own because `hf_cache_enabled` is true,
and it already saw this model there mid-download. **W4 confirms this on the upgraded
build**: `/v1/models` lists `Muse-Glimmer-30B-4bit` with the download complete and no
symlink present. Start here — do not wait for W8.

## Resolution

**Muse Glimmer serves correctly and reproduces, to the second, the latency that
removed it on 2026-08-10.** A 12,882-token prompt waits **64.46 s** for its first
token — against the ~64 s recorded for `Jundot/Muse-Glimmer-30B-oQ4e`. The map treated
this build as unmeasured rather than known-bad, and that was the right call to make;
the measurement now says the two artifacts perform the same. A flat 4-bit quant does
not fix prefill, exactly as the ticket predicted.

Worse, **Bonsai dominates it on every measured axis.** Muse is slower to decode
(26 vs 38 tok/s), no faster to prefill, and costs 2.2× the memory (18.59 vs 8.44 GB).
Whatever argument keeps Muse on the roster keeps Bonsai first.

The one bright spot is memory: this model's KV is the cheapest of the three by a wide
margin, because it is **not** the dense-attention 30B the map assumed — see §3.

### 1. Every functional check passes, at defaults

| Check | Result |
|---|---|
| `finish_reason` | `stop`, on both the trivial and the real coding prompt |
| `content` | `SERVE OK` (8 chars); coding prompt returns a correct 341-char function |
| `reasoning_content` | Split out correctly — 527 chars trivial, 2,414 chars coding |
| Tool calling | `finish_reason: tool_calls`, `read_file` + `{"path":"src/main.py"}`, in **5.28 s** |
| Quantized load | Clean. The vendored mlx-vlm compat patch (`omlx/patches/mlx_vlm_muse_glimmer_compat`) is present and the logits do not collapse — answers are coherent across 6 completions |
| Vision tower | Loads. Discovery reports `size: 18.99GB, text-only: 15.36GB` ⇒ the tower costs **~3.63 GB** |

Settings stay at their defaults. **No `model_settings.json` entry is needed** — the
`reasoning: medium` pin the old `--muse` profile carried (commit `6f6c030`) has no
correctness job to do here. It would only be a *cost* lever; see §6.

**No drafter engaged.** The log contains zero `dflash`, `mtp` or `speculative` lines,
so `dflash-mlx` stayed off as instructed and none of these numbers are a speculative
result.

### 2. Measured cost

MCP-free path, `omlx 0.5.8.dev3`, ai.sh's flags (hot 8 GB, SSD ≤25 GB, guard 48,
concurrency 2). Prefill measured directly at `max_tokens: 1`.

| Quantity | Value |
|---|---|
| Cold model load | **4.64 s** |
| Resident, model only | **18.59 GB** (oMLX's figure; estimated 18.99 GB) |
| Peak resident, 65 k prefill | **21.90 GB** process RSS |
| Decode, coding prompt | **26.0–27.1 tok/s** (3 runs: 27.1 / 26.2 / 26.0) |
| Prefill, 10,064 tok | 54.05 s / 57.34 s ⇒ 176–186 tok/s |
| Prefill, 12,882 tok | **64.46 s / 68.84 s** ⇒ 187–200 tok/s |
| Prefill, 25,064 tok | 154.90 s / 155.70 s ⇒ 161–162 tok/s |
| Prefill, 65,600 tok | 414.16 s ⇒ 158 tok/s |
| Warm restore, 25 k prefix | **3.52–3.79 s** (6,611–7,125 tok/s effective) |

**The gate number is 64.46 s.** The second run at the same size took 68.84 s, so the
honest range is 64–69 s. Either way it sits on top of the ~64 s that killed the last
attempt.

**W5's warm-up artefact did not reproduce**, as it did not for Bonsai: the first run of
each size was the *faster* one, and the two 25 k runs agree to within 0.5 %. No run
needed discarding.

**Prefill scales well and starts badly** — the same shape W6 found. 6.5× the tokens
(10 k → 65 k) costs only 1.2× the per-token rate (186 → 158 tok/s). The constant factor
is the whole problem, and it is what a dense 30B forward pass costs on this box.

**The two-tier cache works**, and honestly: a repeated 25 k prefix comes back in 3.5 s
against 155 s cold, with `cached_tokens: 24576`.

### 3. The KV over-count does not reach this model — and the map's KV facts were wrong

oMLX logs, at load:

```
Model info set: 52 layers (13 KVCache, rotating 39x@2048), 2 KV heads, 32 Q heads,
128 head_dim. Estimated memory per 64-token block: 3.25 MB
```

**This model is not the dense-attention 30B the map assumed.** `config.json` gives
`layer_types` as 3 `sliding_attention` : 1 `full_attention` with
`sliding_window: 2048`, so only **13 of 52 layers** cache KV without bound. The
ticket's ~52 KB/token figure charged all 52.

- Real full-attention KV: 13 × 2 KV heads × 128 head_dim × 2 (K+V) × 2 B =
  **13 KB/token**.
- Rotating layers: 39 × (2048 + chunk − 1) × 1 KB — a **fixed ~0.16 GB**, not a
  per-token cost.
- ⇒ **~1.0 GB at 65 k**, against GLM's 3.5 GB and Bonsai's 4.0 GB. Cheapest on the
  roster.

The printed `3.25 MB` per 64 tokens is 52 KB/token — the all-52-layers figure, **4× the
truth**, exactly the pattern W6 found on Bonsai and for exactly the same reason: it
comes from `estimate_block_memory()`, whose only caller is eviction sizing, and this
server logs `MemoryMonitor initialized (estimator-only, eviction disabled)`. The
**admission** path is `estimate_resident_kv_bytes()`, which charges
`_num_kv_cache_layers` (13, correct) linearly and adds a **saturating** rotating term —
`resident = min(num_tokens, window + chunk - 1)`, `memory_monitor.py:644`. It is right.

**Confirmed empirically.** A 65,600-token prompt **answered** in 414.16 s, peaking at
21.90 GB resident. Model 18.59 + KV ~1.0 + transient ≈ 21.9 GB matches the corrected
figure; the 3.4 GB the log line implies would have shown. The whole session logged
**no `KV+SDPA`, no dynamic ceiling, no throttling, no rejection and no warning of any
kind** past startup. GLM was refused at this size in 5.1 s; Muse is not.

**So GLM's fault stays narrow, and the map's fog patch on this question is now closed.**
Both non-GLM models reach the correct answer by a different route than
`estimate_mla_kv_bytes_per_token`, which is where W5 traced the MLA bug.

### 4. Constraint 7 holds on memory and fails on time

65,536 is reachable — memory is not this model's constraint at any context oMLX will
serve. But **414 s of prefill is 6 m 54 s before the first token**, so the reachable cap
and the usable cap are once again very different numbers. Same conclusion as Bonsai,
one minute cheaper.

**Native window is 131,072**, not the 262,144 the other two carry
(`text_config.max_position_embeddings`), so there is less headroom above 65 k than the
roster average even in principle.

**Long-range recall caveat, new to this model.** Only 13 of 52 layers see the whole
window; the other 39 are limited to 2,048 tokens. This is the Gemma-4 caveat the old
`CLAUDE.md` documents, and sharper — recall of detail far back in a long session is
structurally weaker than "52 layers" suggests. It applies to whatever context cap W9
writes.

### 5. It fits beside the hot cache, and it barely touches the disk

18.59 GB resident + 8 GB hot tier = **26.6 GB**, comfortably under the 40.8 GB soft
threshold. No eviction, no memory-guard event.

**The SSD tier never engaged: zero blocks were written all session.** At 13 KB/token
the 8 GB hot tier holds ~600 k tokens, so nothing was ever evicted to disk — the 25 k
warm restore came from RAM. Against Bonsai's 5.15 → 24 GB in one session (W6), this
model is free on disk. `~/.omlx/cache` began and ended at 4.83 GB, all of it Bonsai
blocks the server reported as `skipped_incompatible=18 blocks (4.83 GB)` — the model
switch orphaned them again, as W6 warned.

### 6. Reasoning cost, for the record

Defaults are correct but not free. A one-line coding question spent **2,414 chars /
~600 completion tokens** on reasoning, ~22 s of a 26.8 tok/s decode. Bonsai spends
~1,300 tokens on the same question but decodes 1.4× faster. If this model survives
W13, `reasoning: medium` is the lever — as a cost measure, not a fix.

### 7. No custom kernel exists for this architecture

`omlx/custom_kernels/` holds `bonsai`, `glm_moe_dsa`, `minimax_m3`, `qwen35_prefill`,
`common` and `nax` — **nothing for `muse_glimmer`**. The only oMLX-specific code for
this model is the vendored mlx-vlm compat patch. So the "unbuilt Metal kernels" fog
patch offers this model no escape at all, unlike Bonsai (where it is a decode-only
option) — there is nothing to build.

### 8. Consequences for the map

- **W13 now decides two models, not one.** It anticipated this exactly: "If both fail
  on prefill, the three-model table in the destination collapses and that is one
  scoping conversation." Both failed. Its body is updated with these numbers.
- **The map's Muse KV facts are corrected** — 13 of 52 layers cache KV; ~13 KB/token,
  ~1.0 GB at 65 k; native window 131,072; 2,048-token sliding window on 39 layers.
- **The KV-over-count fog patch closes.** It reaches neither Bonsai nor Muse; W12 must
  not generalise GLM's cap to the roster.
- **The "what replaces a failed model" fog patch folds into W13** — it is no longer a
  hypothetical.
- **A disk note for W8**: this model writes nothing to the SSD KV tier, so the 25 GB
  budget is sized by Bonsai and GLM alone.

### 9. Measurement hygiene

The log holds **14 chat completions, all `Muse-Glimmer-30B-4bit`, and zero `Embedding:`
lines**, so the MCP-free rule held. Idle `smart-coding-mcp` processes were on the box
and generated no traffic. Only 3 warnings appear, all at startup and all pre-existing
(two duplicate-model-id notices, the Metal-cap notice).

`~/.omlx/cache` was pruned from 23.94 GB to 4.83 GB before the run, oldest-first by
mtime — the same rule `_prune_cache` uses — because free disk was 25 GiB. 451 stale
blocks went; they were GLM's and Bonsai's, already unusable here.

Log: `logs/w7-muse-081953.log`. The server was stopped at the end, leaving the box as
found.
