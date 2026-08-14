---
id: W5
title: Serve-check GLM 4.7 Flash 6-bit and measure it
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: [W1, W4]
---

## Question

Does `lmstudio-community/GLM-4.7-Flash-MLX-6bit` serve real coding turns on oMLX, and
what does it cost? This is the bare `ai` default, so it carries the highest bar.

### Measure

Use the MCP-free measurement path, as the previous profiles did.

1. **Prefill, directly** — `max_tokens: 1` at ~10k and ~25k tokens. Do **not** infer
   prefill by subtracting decode from the log line: oMLX builds report `tok/s`
   differently (end-to-end vs decode-only), so the arithmetic silently disagrees
   between versions. One token of output isolates prefill on either.
2. **Decode** on a short prompt.
3. **Resident memory** with the model loaded, and cold load time.

### Assert, not assume

The response must have **non-empty `content`** and `finish_reason: stop`. Gemma 4
returned 100% `reasoning_content` with empty `content` and ran to the `max_tokens`
cap — which reads as success unless the body is checked. Settings stay at their
defaults unless this check fails; only then pin `enable_thinking`, and remember
oMLX keys `model_settings.json` by the **directory leaf**, so entries must be written
under both spellings.

### Also confirm

- Tool calling works end to end: a request with two tool definitions returns
  `finish_reason: tool_calls` with the name and arguments parsed.
- The model answers at the flat **65,536** context cap without hitting
  `Memory limit exceeded during prefill`. Expected KV is ~3.5 GB at 65k (MLA,
  ~54 KB/token), so the binding risk is the prefill transient, not KV size.
- Resident ~23 GB plus the 8 GB hot cache stays under the memory guard's soft
  threshold (85% of 48 GB = 40.8 GB).

### Note

MTP stays **off** here by decision, even though this model carries an MTP head. A
first run that changes both the model and the decode path cannot attribute a bad
result.

### Gate correction from W1

`max_tokens` must be **1024 or above**. W1 measured that a short cap returns the whole
reasoning inline in `content` with **no `reasoning_content` key**, so the pair
(non-empty `content`, `finish_reason: stop`) only holds when the reasoning block gets
room to close. GLM needed 252 tokens for a one-line answer.

### Correction from W2 — there is no MTP head to leave off

The Note above says MTP stays off "even though this model carries an MTP head". W2
found that is not true of this checkpoint. `config.json` declares
`num_nextn_predict_layers: 1`, but **0 of the 1970 tensors** in
`model.safetensors.index.json` match `mtp`/`nextn` — the 6-bit conversion dropped the
head. Upstream also excludes `glm4_moe_lite` from `_is_mtp_compatible()`, and its
"GLM MTP patch" targets GLM-5.2's `glm_moe_dsa`, a different model.

So MTP is not a decision here, it is unavailable. Two consequences:

- Do not write an `mtp_enabled` entry for this model, and do not read a flat decode
  rate as "MTP failed to engage".
- The sanitize hazard is absent too. oMLX applies its MTP patch even when
  `mtp_enabled` is false, because stock mlx-lm shifts norms by +1 on seeing `mtp.*`
  keys and double-shifts an already-converted checkpoint into garbage. With no such
  keys, there is nothing to shift.

## Resolution

**GLM 4.7 Flash serves correctly and decodes well, but it cannot run at 65,536
context on this box.** The cause is not the model and not real memory. oMLX sizes
this model's MLA KV cache with the plain MHA formula and over-counts it by **7×**,
so the prefill memory guard rejects long prompts long before memory is at risk.

The model keeps the bare `ai` default. Its context cap is now an open decision —
see the new ticket below.

### 1. The gate passes

| Check | Result |
|---|---|
| `finish_reason` | `stop` |
| `content` | `SERVE OK` — non-empty, the answer only |
| `reasoning_content` | 493 chars, split out correctly |
| `max_tokens` | 1024, as W1 requires |

Settings stay at their defaults. **No `enable_thinking` pin is needed**, and no
`model_settings.json` entry is written for this model at all.

**Tool calling works end to end.** A request with two tool definitions returns
`finish_reason: tool_calls` with `read_file` and `{"path": "src/main.py"}` parsed,
in 9.7 s.

### 2. Measured cost

Measured on the MCP-free path against `v0.5.8.dev3`, with the flags `ai.sh` passes.

| Quantity | Value |
|---|---|
| Cold model load | 5.5–8.9 s |
| Resident, model only | **22.89 GB** (oMLX's own figure); process 23.0–23.8 GB |
| Decode, short prompt | **~68 tok/s** (50.6 / 68.6 / 67.7 over three runs) |
| Cold prefill, fresh prefix | **~590 tok/s** (14,909 tok in 24.93 s; 14,953 tok in 25.45 s) |
| Warm prefix restore | **1.0–2.0 s** for the same 14.9k prompt |

Prefill is measured directly at `max_tokens: 1`, as the ticket requires.

**Two readings that mislead, recorded so nobody repeats them:**

- **The first large prefill after a model load costs about twice the steady rate** —
  14,896 tokens in 45.13 s (330 tok/s) against ~590 tok/s for every later cold
  prefix. Warm-up is a one-time cost. Do not quote the first run as the rate.
- **A prefix repeated immediately after its cold run does not hit the cache.** The
  first repeat took 39.43 s while reporting `cached_tokens: 14848`; the same prompt
  later took 1.97 s, then 1.41 s, then 0.98 s. The reported hit count is therefore
  not proof of a restore. On a fresh prefix the cache hits on the very first repeat
  (24.93 s → 1.97 s), so this is warm-up too, not a cache defect.

**The two-tier cache works well.** A warm prefix restores at 7,500–15,000 tok/s
effective. Blocks do reach the SSD tier — a later server start indexed 320 files
and 4.13 GB from `~/.omlx/cache`.

### 3. The blocker — oMLX charges 362 KB/token for a 53 KB/token cache

`config.json` gives `kv_lora_rank: 512`, `qk_rope_head_dim: 64` and 47 layers, so
real MLA KV is `47 × 576 × 2 B` = **52.9 KB/token**, which matches the map's ~54.

oMLX logs this instead:

```
Model info set: 47 layers (47 KVCache), 20 KV heads, 20 Q heads, 102 head_dim.
Estimated memory per 64-token block: 23.41 MB
```

`102` is `hidden_size 2048 / 20 heads`, so this is the MHA fallback. It charges
`47 × 20 × 102 × 2 × 2 B` ≈ **362 KB/token** — **7× the truth**. Every rejection
message below confirms the same figure.

**Root cause.** `estimate_mla_kv_bytes_per_token` (`omlx/memory_monitor.py:1219`)
counts MLA layers by reading `layer_cache.caches` on each entry, which only exists
on a `CacheList`. GLM-5.2's `glm_moe_dsa` has one because its DSA indexer adds a
second cache. Our `glm4_moe_lite` layers are bare `KVCache`, so the loop counts zero
main-cache layers, the function returns `None`, and the scheduler falls back to the
uniform MHA formula. The docstring even warns that the fallback "over-counts GLM-5.2
by more than an order of magnitude" — the same trap, one model along.

The scheduler's own MLA detector (`scheduler.py:2916`) reads `kv_lora_rank` off the
config and would identify this model correctly, but it only gates TurboQuant. It
never reaches the estimator. Its log line never appears.

### 4. What the over-count does — measured

| Prompt | Result |
|---|---|
| 20,450 tok | **Answers**, 78.6 s end to end, even at 36 GB in use |
| 37,511 tok | Prefills once on a fresh server, 123 s, chunk throttled 2048 → 896 |
| ~37,500 tok | **Rejected** mid-session at 33.51 GB in use |
| 45,000 tok | **Rejected** after 145 s of wasted prefill (KV+SDPA charged 16.28 GB) |
| ~50,000 tok | **Rejected** after ~9 min, with the hot cache cut to 2 GB |
| 65,000 tok | **Rejected in 5.1 s** on a freshly loaded server (KV+SDPA charged 23.72 GB) |

The 65k rejection is the decisive one. The model is alone in memory at 23.01 GB, and
oMLX still refuses:

```
Prefill would require ~46.74 GB peak (current 23.01 GB + KV+SDPA 23.72 GB)
but dynamic ceiling is 45.12 GB
```

Real KV for that prompt is ~3.5 GB.

**The over-count is not only accounting.** A rejected 45k prefill first drove real
process memory to 36.37 GB, and a 50k prefill reached 36.54 GB. The paged block pool
sizes its blocks from the same estimate, so the wrong number is also allocated. This
matters: correcting the estimate is therefore expected to fix throughput and
capacity together, but it is not a pure bookkeeping change.

**Throttling has the same cause.** From ~25k tokens up, the scheduler cuts the
prefill chunk from 2048 to ~900 (`per_token=21307.6KB`), which roughly halves
prefill throughput. The 20k turn that succeeded ran at ~320 tok/s, not ~590.

### 5. Levers tested

| Lever | Result |
|---|---|
| `--memory-guard-gb` 48 → 54 | **Fails.** The Metal cap takes over: `metal_cap ceiling is 48.77 GB` against Apple's 51.84 GB. Needs `sudo sysctl iogpu.wired_limit_mb`, a system-wide change that belongs to the user, not this map. |
| `--hot-cache-max-size` 8GB → 2GB | **Fails.** 50k still rejected. It buys headroom but not enough. |
| TurboQuant KV compression | **Unavailable.** oMLX disables it for MLA models by design (#1613). |
| A per-model KV override | **Does not exist.** `model_settings.py` has no KV-bytes field. `max_context_window` can cap the model server-side. |

### 6. Consequences for the map

- **Constraint 7 fails for GLM.** A flat 65,536 for all three models is not
  reachable. The clean single-variable comparison the map wanted is not available
  for this model on this box.
- **Constraint 11 is out of date, in our favour.** Disk free rose from 11.52 GB to
  **56.79 GB** during this ticket, with no action taken. W4 called the space
  purgeable and macOS released it. Disk is now 95% full with 46 GB free.
- **W9 must not hard-code 65,536 for GLM.** It now waits on the new ticket.

### 7. One measurement discarded

A 32k/45k run between 00:48 and 00:57 is not reported. A `smart-coding-mcp` indexer
and an interactive `opencode` session started on the box and drove `bge-m3`
embedding traffic through the same server, which breaks the MCP-free rule. Every
number above comes from a log with zero `Embedding:` lines. The affected run was
repeated cleanly afterwards.
