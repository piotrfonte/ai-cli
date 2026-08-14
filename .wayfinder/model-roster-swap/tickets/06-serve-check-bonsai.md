---
id: W6
title: Serve-check Ternary Bonsai 27B 2-bit and measure it
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: [W1, W4]
---

## Question

Does `prism-ml/Ternary-Bonsai-27B-mlx-2bit` serve real coding turns on oMLX, and what
does it cost? This becomes `--bonsai`.

### What makes this one different

- It is a **VLM** (`Qwen3_5ForConditionalGeneration`) with
  `language_model_only: False`, so the vision tower loads whether or not we use it.
  Vision is out of scope for this map; confirm it does not block text serving and
  record what it costs in resident memory.
- The quant is **ternary g128** — weights in {−1, 0, +1} with FP16 group scales,
  ~1.71 bits information-theoretically, deployed at 2.125 bpw. This is not a flat
  affine quant, so confirm the upgraded mlx-lm actually loads it rather than failing
  or silently degrading.
- The card claims a **4-bit KV cache**. Verify whether oMLX honours that or caches at
  fp16 — it changes KV from ~16 KB/token to ~65 KB/token.

### Measure

Same protocol as W5: prefill directly with `max_tokens: 1` at ~10k and ~25k, decode
on a short prompt, resident memory, cold load. Assert **non-empty `content`** and
`finish_reason: stop`. Confirm tool calling end to end.

### Expect

Dense 27B, so prefill is the thing to watch — but 48 of its 64 layers are linear
attention, which should make long-context prefill scale far better than a plain
dense model. That is the interesting measurement here.

### Gate correction from W1

`max_tokens` must be **1024 or above**. W1 measured that a short cap returns the whole
reasoning inline in `content` with **no `reasoning_content` key**, so the pair
(non-empty `content`, `finish_reason: stop`) only holds when the reasoning block gets
room to close. GLM needed 252 tokens for a one-line answer.

### Read the estimator line — added by W5

W5 found that oMLX sized GLM's KV cache **7× too high** and its prefill memory guard
then rejected a 65k prompt in 5.1 s. This model is a stronger candidate for the same
fault: only **16 of its 64 layers cache KV**, so a uniform all-layers formula
over-counts it 4× before the ternary quant and any 4-bit KV are considered.

At model load, oMLX logs a line of the form:

```
Model info set: N layers (N KVCache), K KV heads, Q Q heads, D head_dim.
Estimated memory per 64-token block: X MB
```

Record it, and compare `X` against the KV the config really implies. Report the
implied KB/token either way — the number feeds
[Decide GLM's context cap against oMLX's 7x MLA over-count](12-glm-context-cap.md),
which may set the cap for all three models.

Also measure with `~/.omlx/cache` state in mind: W5 found the **first** large prefill
after a model load runs at about half the steady cold rate, and that a prefix
repeated immediately after its cold run can report `cached_tokens` without actually
restoring. Discard the first run of each size.

## Resolution

**Bonsai serves correctly on every functional check, and it is the cheapest model on
the roster by memory — but it prefills at ~170–210 tok/s, which puts time to first
token on a 12.8k agentic turn at 66.2 s.** That is the same number that removed the
previous `--muse` profile on 2026-08-10 (~64 s). The model works; it is the latency
that does not.

The KV worry this ticket was sent to check is **unfounded**. oMLX classifies the
hybrid layers correctly on the path that matters, 65,536 context is reachable, and
the run produced zero warnings, zero throttling and zero rejections.

Whether Bonsai stays in the roster is a scoping decision, not this ticket's to make —
see the new ticket at the end.

### 1. Every functional check passes

| Check | Result |
|---|---|
| `finish_reason` | `stop` |
| `content` | `SERVE OK` — non-empty, the answer only |
| `reasoning_content` | 771 chars, split out correctly |
| Tool calling | `finish_reason: tool_calls`, `read_file` + `{"path": "src/main.py"}`, in **3.11 s** |
| Ternary g128 quant | **Loads.** oMLX applies a dedicated `bonsai_t5_load` patch ("t5 uint8 weights allowed past strict shape check"); 8.44 GB actual against 8.30 GB estimated |
| Vision tower | Loads, does not block text serving. Discovery reports `size: 8.30GB, text-only: 7.40GB` ⇒ the tower costs **~0.90 GB** |

Settings stay at their defaults. **No `model_settings.json` entry is needed.**

**Correct the gate floor: 1024 `max_tokens` is too low for this model.** The W1 rule
passes on a trivial prompt but fails on a real one. Asked to write a linked-list
reversal at `max_tokens: 1024`, all three runs returned `finish_reason: length` with
the reasoning inline in `content` and **no `reasoning_content` key** — precisely the
dead answer W1 warned about. The same prompt at **4096** returns `finish_reason: stop`,
`reasoning_content` 5202 chars, `content` 430 chars, and a correct function. This model
spends ~1300 reasoning tokens on a trivial question, so the gate needs **4096**.

**MTP is unavailable, as it was for GLM.** `config.json` declares
`mtp_num_hidden_layers: 1`, but **0 of the 2180 tensors** match `mtp`/`nextn`. oMLX
detects this and logs that it skipped MTPModule attachment "to keep strict
load_weights happy". Do not write an `mtp_enabled` entry, and do not read a flat
decode rate as MTP failing to engage.

### 2. Measured cost

MCP-free path, `omlx 0.5.8.dev3`, ai.sh's flags (hot 8 GB, guard 48, concurrency 2),
SSD cache capped at 25 GB. Prefill measured directly at `max_tokens: 1`.

| Quantity | Value |
|---|---|
| Cold model load | **2.89 s** |
| Resident, model only | **8.44 GB** (oMLX's figure); process 8.74 GB |
| Peak resident, 12.8k prefill | 16.69 GB |
| Peak resident, 65k prefill | 16.68 GB |
| Decode, short prompt | **37.9–40.3 tok/s** |
| Prefill, 10,018 tok | 47.29 s / 54.86 s ⇒ 183–212 tok/s |
| Prefill, 12,818 tok | **66.20 s** ⇒ 194 tok/s |
| Prefill, 25,018 tok | 147.52 s / 151.22 s ⇒ 165–170 tok/s |
| Prefill, 65,554 tok | 443.82 s ⇒ 148 tok/s |
| Warm restore, 25k prefix | **3.35–3.93 s** (6,362–7,479 tok/s effective) |

**The two-tier cache works.** A 25k prefix restores in ~3.5 s against ~150 s cold, and
`cached_tokens` reported 24,576 honestly on the first repeat.

**W5's warm-up artefact did not reproduce.** The first 10k run was *faster* than the
second (47.29 s vs 54.86 s) and the two 25k runs sit within 2.5 % of each other. No
run needed discarding on this model; the rates above are stable as measured.

**Against the rest of the roster, prefill is the outlier:** GLM ~590 tok/s, Macaw
~1,850–2,270 tok/s, Bonsai ~194 tok/s. Decode is unremarkable but fine (GLM ~68,
Macaw ~59, Bonsai ~38).

**The linear-attention hypothesis is half right.** The ticket expected 48 of 64 layers
being linear attention to make long-context prefill scale well. Scaling *is* good —
6.5× the tokens (10k → 65k) costs only 1.4× the per-token rate (212 → 148 tok/s), far
flatter than quadratic. But the **constant factor** is the problem, and linear
attention does nothing for it.

### 3. The KV over-count does not reach this model

oMLX logs the line the ticket asked for:

```
Model info set: 64 layers (16 KVCache), 4 KV heads, 24 Q heads, 256 head_dim.
Estimated memory per 64-token block: 16.00 MB
```

**It reads both right and wrong at once.** The layer classification is correct — it
found exactly **16 KVCache** layers of 64, matching `layer_types`. But 16.00 MB per
64 tokens is **256 KB/token**, which is `64 × 4 × 256 × 2 × 2 B` — the *all-layers*
figure. Real KV is `16 × 4 × 256 × 2 × 2 B` = **64 KB/token**. The printed estimate is
**4× the truth**, exactly as the ticket predicted.

**It does not matter, and that is the finding.** The two numbers come from different
functions:

- `estimate_block_memory()` (`memory_monitor.py:533`) uses `self._num_layers` — all 64.
  This is what the log line prints. Its only caller is `estimate_blocks_to_free()`,
  and this server logs `MemoryMonitor initialized (estimator-only, eviction disabled)`,
  so nothing calls it.
- `estimate_prompt_kv_bytes()` / `estimate_resident_kv_bytes()` (`:574`, `:613`) use
  `self._num_kv_cache_layers` — 16, correct — plus a saturating rotating-window term
  and a GDN fixed-state term measured after the first chunk. **This is the admission
  path**, and it is right.

Empirically confirmed: the 65k prefill peaked at **16.68 GB** resident. Model 8.44 GB
plus real KV 4.00 GB plus transient matches that; the 16.00 GB of KV the log line
implies would have been refused outright, as it was for GLM.

**The card's 4-bit KV claim is not honoured.** The cache signature line reads
`turboquant_kv_bits=None` and the estimator was handed `dtype_size=2`, so KV is stored
at fp16/bf16. Take **64 KB/token**, not the ~16 the card suggests — ~4.0 GB at 65k,
~16 GB at the native 262,144.

**So GLM's fault stays narrow.** W5 traced it to `estimate_mla_kv_bytes_per_token`
recognising MLA only through a `CacheList`. Bonsai reaches the correct answer by a
different route — `collect_kv_layer_specs(model.make_cache())` classifies its hybrid
layers properly — so the two models do not share a bug. The map's fog patch on this
question is now answered for Bonsai and still open only for Muse Glimmer.

### 4. 65,536 context is reachable — constraint 7 holds here

A 65,554-token prompt **answered**, in 443.82 s, with the model alone in memory. The
log contains no `KV+SDPA`, no `dynamic ceiling`, no chunk throttling and **no warnings
or errors of any kind** across the whole session. GLM was rejected at the same size in
5.1 s; Bonsai is not.

Memory is not this model's constraint at any context oMLX will serve. **Time is.** At
148 tok/s a full 65k window costs **7 minutes 24 seconds** before the first token, so
the reachable cap and the usable cap are very different numbers.

### 5. The unbuilt Metal kernels will not rescue this

The map's fog held this open pending a kernel-free baseline. The baseline is above,
and the answer is no:

- `omlx.custom_kernels.bonsai` is a **decode** kernel — "fast affine quantized matrix-
  **vector** kernels for decode (M = 1..5 input rows)", plus a speculative-decode
  verify. `has_native()` returns `False` here, so building it with
  `OMLX_WITH_CUSTOM_KERNEL=1` would lift the ~38 tok/s decode and touch prefill not
  at all.
- The **prefill** kernel is already engaged without building anything.
  `omlx.patches.qwen35_gdn_chunked` logs `impl=blocked_seq`, and its docstring names
  that the default and fastest route — "~2x faster than mlx_lm's stock sequential
  kernel at 16k". The alternative (`OMLX_GDN_IMPL=chunked`) is documented as *slower*
  end to end.

The 194 tok/s is therefore oMLX's best current effort on this architecture, not a
misconfiguration.

### 6. Consequences for the map

- **Constraint 7 survives for Bonsai** but is now known to fail for GLM only. A flat
  65,536 is reachable here; whether it is *sensible* is a latency question.
- **Constraint 9 needs sharpening**: the serve gate's `max_tokens` floor rises from
  1024 to **4096**. W7 must use 4096 or it risks scoring Muse Glimmer on a truncated
  answer.
- **W12 gains a data point.** The over-count is GLM-specific. Bonsai needs no lowered
  cap for memory reasons, so W12 should not generalise its answer to the roster.
- **A KV-cache budget note for W8**: `~/.omlx/cache` grew from 5.15 GB to **16 GB**
  during this one session, against the proposed 25 GB cap. Bonsai's blocks are large
  (64 KB/token at fp16) and a model switch orphans everything — the server logged
  `skipped_incompatible=399 blocks (5.15 GB)`, GLM's entire cache, unusable here. 25 GB
  is workable but not generous.
- **The roster decision is now live** — see below.

### 7. Measurement hygiene

Every number comes from a log with **zero `Embedding:` lines** and no completion served
for any model other than Bonsai, so the MCP-free rule held throughout. An idle
`opencode` and `smart-coding-mcp` were running on the box, but the oMLX server was down
when this session began and they generated no traffic against it. Log:
`logs/w6-bonsai-011248.log`. The server was stopped at the end, leaving the box as
found.

### 8. New ticket

Bonsai passes every functional bar and fails the latency bar that has already removed
one model from this roster. The map's own fog says replacing a model that fails its
serve check "is a scoping decision, not a substitution this map can make on its own",
and the decision is better made once W7 reports, because both remaining questions are
about the same failure mode. Raised as
[Decide the roster now that Bonsai prefills at ~200 tok/s](13-roster-after-prefill.md),
blocked by W7.
