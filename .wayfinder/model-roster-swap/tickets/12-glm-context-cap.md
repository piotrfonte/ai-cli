---
id: W12
title: Decide GLM's context cap against oMLX's 7x MLA over-count
map: model-roster-swap
labels: [wayfinder:grilling]
status: closed
assignee: claude
blocked_by: [W5]
---

## Question

W5 proved that oMLX charges GLM 4.7 Flash **362 KB/token** of KV cache when the real
MLA cost is **52.9 KB/token**, and that its prefill memory guard therefore rejects a
65,536-token prompt in 5.1 s on a freshly loaded server. Constraint 7 of the map — a
flat 65,536 for all three models — is not reachable for this model as things stand.

**What context does bare `ai` declare, and do we correct the estimate or live with
it?** The answer sets `limit.context` for GLM in `opencode.json`, so W9 waits on it.

Read the resolution of [Serve-check GLM 4.7 Flash 6-bit and measure it](05-serve-check-glm.md)
first. It holds the measurements, the root cause in `omlx/memory_monitor.py:1219`,
and the levers already tested and ruled out.

### The three options

**A. Cap GLM's context low and change nothing else.** Measured: 20,450 tokens answers
end to end even at 36 GB in use; ~37,500 tokens prefills only on a fresh server and
is rejected mid-session. A cap near **24,576** looks safe, and **32,768** is the
optimistic end. Costs nothing, carries no patch, and gives up roughly half the
context the map wanted.

**B. Raise Apple's Metal working-set cap.** `sudo sysctl iogpu.wired_limit_mb=57344`,
as `CLAUDE.md` already records. This is a system-wide change the user must make and
must re-apply after a reboot. It moves the ceiling but does **not** fix the
over-count, so the guard still rejects far earlier than real memory requires. W5
measured that raising `--memory-guard-gb` alone to 54 does not help, because the
Metal cap becomes the binding ceiling at 48.77 GB.

**C. Correct the estimator.** `estimate_mla_kv_bytes_per_token` fails only because it
counts MLA layers through `layer_cache.caches`, which exists on a `CacheList` but not
on the bare `KVCache` that `glm4_moe_lite` uses. The scheduler already detects MLA
correctly from `kv_lora_rank` at `scheduler.py:2916`, but only to gate TurboQuant.
This repo has an established pattern for exactly this — idempotent patch scripts
re-applied on every launch — so a `scripts/patch-omlx-mla-kv.mjs` would fit the
architecture. It is also the only option that recovers the full 65,536.

**D. Serve GLM from a smaller quant — added by [W13](13-roster-after-prefill.md).**
`lmstudio-community/GLM-4.7-Flash-MLX-4bit` is **15.70 GB** against the current 6-bit
build's 22.67 GB, native MLX affine, and loads with no patching at all. The guard
rejects on estimated KV **plus resident weight** against the Metal cap, so ~7 GB of
freed weight buys context back directly — without a patch and without a sysctl. It is
the only option that needs neither maintenance debt nor a system change.

Its costs: a 15.70 GB download onto a disk with ~15 GiB free, an unmeasured quality
drop from 6-bit to 4-bit, and a repeat of W5's serve check. **The user has chosen to
keep the current 6-bit build for now**, so this is an option to weigh, not a decision
already taken — but it should be weighed before a low cap is accepted as permanent.

Note also that `unsloth/GLM-4.7-Flash-NVFP4` is **not** a candidate. It is a
compressed-tensors `mixed-precision` checkpoint that mlx-lm mis-declares as
int4-affine-g32; W13 §5 records the full chain.

### What makes this a judgement call, not a lookup

- A patch against a third-party server is **maintenance debt**, and the map's
  constraint 5 deliberately chose one build upgraded in place. A Python patch script
  is new ground: every existing `scripts/*.mjs` patches JSON config or a JS plugin,
  never oMLX's own source.
- The over-count is **not purely cosmetic**. W5 measured real process memory reaching
  36.4 GB during a rejected 45k prefill, because the paged block pool sizes its
  blocks from the same estimate. Correcting the estimate should improve throughput
  and capacity together, but the change is not risk-free, and a wrong KV estimate in
  the other direction ends in a hard Metal failure rather than a clean rejection.
- Upstream may fix this. The target is a `.dev` tag, and the docstring shows the
  author already met this bug once on GLM-5.2.

### Decide as well

- Whether the other two models keep 65,536, or whether all three drop to GLM's
  number to preserve the clean single-variable comparison constraint 7 wanted. W6 and
  W7 report their own estimator lines, so the sizes will be known.
- Whether `max_context_window` in `model_settings.json` should mirror the
  `opencode.json` cap, so a stray client cannot send a prompt the guard will reject
  after minutes of wasted prefill. W5 measured a 45k rejection arriving only after
  145 s.

### Acceptance

A number for `limit.context` for GLM in `opencode.json`, a decision on options A/B/C
with its reasoning, and — if C wins — a patch script validated the way the map's
Notes require, plus a re-run of W5's 65k check to prove it.

## Resolution

**GLM declares `limit.context: 32768`. Option C was taken and works — but it does not
deliver 65,536, because the over-count was never the real blocker.** Correcting the
estimate was still right: it removes a 7.08x accounting error and the prefill throttle
that error triggered from ~25k tokens up. It just turned out to be masking a second,
opposite defect.

| Setting | Value | Job |
|---|---|---|
| `limit.context` (`opencode.json` — **W9 writes this**) | **32,768** | the client's budget |
| `max_context_window` (`model_settings.json`, written by `patch-omlx-mtp.mjs`) | **36,864** | safety rail |

Measurements, scripts and the three discarded runs are in
[assets/w12-mla-kv-cap](../assets/w12-mla-kv-cap/).

### 1. The root cause is one level deeper than this ticket assumed

The ticket said `estimate_mla_kv_bytes_per_token` "fails only because it counts MLA
layers through `layer_cache.caches`". That loop is real, and it is **unreachable for
this model**. `mlx_lm/models/glm4_moe_lite.py` defines **no `make_cache`**, so the
scheduler's `if not hasattr(self.model, "make_cache")` branch leaves
`cache_list_for_tq` at `None` (`scheduler.py:11580`) and the estimator returns at its
`if cache_list is None` check, before any layer counting.

A patch to the loop alone therefore changes nothing. That was written, applied, and
caught only because the guard's arithmetic still implied ~358 KB/token afterwards; it
was reverted. The shipped patch fixes the `cache_list is None` branch — deriving the
layer count from the config, which is exact here because `glm4_moe_lite` is uniform
full attention (no `layer_types`, no `sliding_window`) — and also hardens the loop for
the day mlx-lm gives this model a `make_cache`.

oMLX's **vendored** `glm_moe_dsa` (`omlx/patches/glm_moe_dsa/glm_moe_dsa_model.py:501`)
does define `make_cache`, so GLM-5.2 keeps the original `CacheList` path untouched.

### 2. The correction is live and exact

`47 x (512 + 64) x 2 B` = **52.9 KB/token**, against ~374 charged before — **7.08x**.
KV at 65 k falls from 23.41 GB to 3.30 GB. The server now logs:

```
Model info set: 47 layers (47 KVCache), 20 KV heads, 20 Q heads, 102 head_dim.
Estimated memory per 64-token block: 3.30 MB, KV override 52.88 KB/tok
```

Blast radius is one model: the estimator returns `None` before the patched lines
unless the config carries both `kv_lora_rank` and `qk_rope_head_dim`. Verified — GLM
has both (512 / 64); Bonsai (`qwen3_5`) and Muse (`muse_glimmer`) have neither and are
untouched with or without a cache list.

### 3. Why 65,536 is still out of reach — the binding constraint was never KV

With KV priced honestly the guard **admits** 45,072 tokens, and then real memory does
what the old estimate wrongly predicted for the wrong reason:

```
Memory pressure level: ok -> hard (current=48.1GB, soft=40.8GB, hard=45.6GB)
Prefill force-stopped at 20608 tokens: memory 50.3GB exceeds physical cap 50.3GB
Unloading model: GLM-4.7-Flash-MLX-6bit (immediate abort)   freed=36.13GB
```

The cost is the prefill **activation** transient, not the cache. The guard prices it
badly in the other direction — it quoted `KV+SDPA 1.55 GB` for a step whose real
transient exceeded 14 GB. **So option C removed a safety net**: before it, the inflated
KV rejected these prompts cleanly; after it, they are admitted and abort mid-prefill,
costing ~5 minutes and a model unload. That is the failure mode this ticket's own risk
note warned about. Section 5 is how it is put back.

Measured ladder, each rung a fresh prefix (cold door charge):

| Cold prompt | Result | Time | Rate |
|---|---|---|---|
| 10,256 | OK (warm-up) | 18.83 s | 545 tok/s |
| 24,592 | OK | 75.17 s | 327 tok/s |
| 32,783 | OK | 116.00 s | 283 tok/s |
| 40,976 | OK | 266.09 s | 154 tok/s |
| 40,975 (+4,096 out) | OK — `stop`, `SERVE OK` | 319.73 s | — |
| 45,072 | **FAILS** | ~5 min lost | — |

**40,960 passes only by winning a race.** The server pauses the request, evicts pooled
Metal buffers and resumes at a smaller chunk; at 45,072 the prefill reaches the
physical cap before the throttle reacts. Numbers at that edge are not reliably
repeatable. Cost also grows far faster than length — 1.25x the tokens from 32,783 to
40,976 costs **2.3x** the time.

**32,768 is therefore the declared number**, not 40,960: it keeps ~8k of margin below
the last passing rung, costs less than half the door charge, and leaves headroom for
the hot cache and a concurrent summarizer — W5's warning that safe-when-fresh is not
safe-mid-session still stands.

### 4. Options B and D, revisited honestly

- **B (sysctl) was declined on a premise that this ticket then broke.** It was rejected
  partly because it "does not fix the over-count". The over-count is now fixed, and the
  Metal cap is the literal binding ceiling (`memory 50.3GB exceeds physical cap
  50.3GB`). Raising it would now buy context directly. Raised as
  [Buy prefill headroom for GLM: Metal cap, hot-cache size and the 4-bit re-quant](17-glm-prefill-headroom.md).
- **D (4-bit re-quant) is permitted but not taken.** The user reopened it during this
  ticket. It is not needed for context — C is free and D would not have fixed the
  accounting — but its ~7 GB of freed weight attacks the *transient* ceiling directly,
  so it belongs with the other headroom levers, measured against a stable baseline
  rather than on the same day the estimator changed.
- **E (`--memory-guard off`) was found and rejected.** `omlx serve --memory-guard off`
  exists (`cli.py:899`). It would remove the clean rejection entirely and turn every
  overrun into the abort seen in section 3.
- `OMLX_PREFILL_WATERMARK_SHARE` is **not** a context lever. It sizes prefill chunks
  after the throttle engages, so it addresses W5's 2048→896 slowdown only.

### 5. The safety rail, and why the two numbers differ

`validate_context_window` (`server.py:1618`) runs on the tokenized prompt **before**
scheduling, so a pinned `max_context_window` rejects instantly — ahead of the guard's
now-under-priced admission. That is what restores what section 3 removed.

Unpinned, oMLX resolves the cap from the model's *native* window (202,752 for GLM), so
any client that never reads `opencode.json` — the opencode-mem summarizer,
smart-coding, a stray script — could send a prompt far past what this box can prefill.

**The rail must not equal the budget.** Mirroring them was tried and failed: a prompt
built for 32,768 rendered as **32,784** tokens and was hard-rejected, because opencode
estimates tokens with its own tokenizer. The rail is therefore the declared context
plus one 4,096-token block. Applied to all three models for consistency:

| Model | Declares | Rail |
|---|---|---|
| GLM 4.7 Flash | 32,768 | 36,864 |
| Ternary Bonsai | 65,536 | 69,632 |
| Muse Glimmer | 65,536 | 69,632 |

Verified after the change: 45,072 tokens → clean HTTP 400 in **1.67 s**; 32,784 tokens
→ serves, `finish_reason: stop`, `SERVE OK`, 96.79 s.

### 6. What shipped

- `scripts/patch-omlx-mla-kv.mjs` — new. Idempotent, sentinel-guarded, one anchor in
  `omlx/memory_monitor.py`. oMLX is an **editable** install, so there is one file to
  patch, not two. Exit **3** on a missing anchor, which `ai.sh` treats as a degrade
  signal. Tested fresh-apply, idempotent re-run, missing dir, missing anchor, ambiguous
  anchor, usage error, and `py_compile` of the result.
- `ai.sh` — runs the patch before the server starts, and appends **`+mlakv`** to the
  recorded build string on success, so the existing state-file build check restarts a
  server still running the old module. **This changes the state file's line 2 format**
  that W8 recorded as `<binary>@<git HEAD>`; W11 should document it.
- `ai.sh` — Q9(c) fail-safe: if the anchor is gone, it injects `limit.context: 24576`
  for GLM through `OPENCODE_CONFIG_CONTENT` for that session only, reusing the MCP
  kill-switch's overlay, and warns. Verified to compose with that overlay.
- `scripts/patch-omlx-mtp.mjs` — `DESIRED` is no longer empty; it carries the three
  rails. Re-tested for fresh-create, idempotency, preserving a foreign model and an
  admin-set key, and corrupt-file recovery.
- `CONTEXT.md` — four terms added: *charged KV*, *real KV*, *prefill admission*,
  *prefill throttle*. The first pair is why the wrong patch was written.

### 7. Consequences for the map

- **Constraint 7 is now definitively broken for GLM**, and not by the accounting bug it
  blamed. A flat 65,536 across three models is unreachable on this box.
- **W9 must write 32,768 for GLM**, and 65,536 for the other two.
- **W14's comparison is no longer single-variable.** GLM runs at half the context of
  the other two, so a capability result cannot be read as model-vs-model alone.
- **W11 must document** the new state-file format, the patch script, and the fact that
  `ai` now depends on a patched third-party file.
