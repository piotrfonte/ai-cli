---
id: W17
title: Buy prefill headroom for GLM — Metal cap, hot-cache size and the 4-bit re-quant
map: model-roster-swap
labels: [wayfinder:grilling]
status: closed
assignee: claude
blocked_by: [W12]
---

## Question

[W12](12-glm-context-cap.md) settled GLM's cap at **32,768** and proved the binding
constraint is **not** KV. It is the prefill activation transient hitting the physical
Metal cap:

```
Prefill force-stopped at 20608 tokens: memory 50.3GB exceeds physical cap 50.3GB
Unloading model: GLM-4.7-Flash-MLX-6bit (immediate abort)   freed=36.13GB
```

Three levers buy headroom against exactly that ceiling. **Is any of them worth taking,
and does GLM then declare more than 32,768?**

### Re-framed by W18 — GLM is no longer the default

[W18](18-default-after-capability.md) moved bare `ai` to Muse Glimmer, so **every lever
below is now spent on an opt-in profile**, and the prices have moved with it:

- **Lever A is unchanged.** A free, reversible sysctl still helps whatever runs.
- **Lever B looks worse.** Cutting `OMLX_HOT_CACHE` taxes all three profiles, and the tax
  now lands on the *default's* warm restores to widen a profile you opt in to.
- **Lever C looks worse.** A 15.70 GB download and an unmeasured capability drop, spent on
  a model that no longer serves bare `ai`. Note the drop is now *less* dangerous for the
  same reason — it no longer degrades the default.
- **The urgency is gone.** The "shortest usable window on the roster" objection described
  the default when this ticket was written. The default now declares **65,536**; 32,768
  describes the fast profile you reach for deliberately.

This ticket stays open and keeps all three levers on the table — the trade is still real
for anyone who reaches for `--glm` on a long file — but it sits **below**
[Measure GLM with thinking pinned off](19-glm-thinking-pin.md) in priority. If that ticket
returns GLM to the default, re-read this one at its original prices.

### W19 has settled that conditional — the re-framed prices are final

**GLM did not retake the default.** W19 pinned thinking off, removed every runaway, and
watched solved fall 6/12 → 4/12 against a floor of 9. So the reduced prices above are the
real ones, permanently: every lever here is spent on an **opt-in** profile, and the
"shortest usable window on the roster" objection stays retired.

W19 sharpens one point in this ticket's favour and one against:

- **For** — GLM is now firmly the *fast* profile and nothing else. Whoever types `--glm`
  is reaching for speed on a big file, which is exactly what lever A or C buys. Nothing
  competes for the profile any more.
- **Against** — W19 measured GLM solving **4–6 of 12** short coding tasks either way.
  Widening the window of a model that fails more than half of them is a genuine question
  of worth, and it should be answered before any lever is bought. Buying context is not
  buying capability, and this map has no evidence the two connect.

Read W12's resolution first — especially §3, which holds the measured ladder, and
[assets/w12-mla-kv-cap](../assets/w12-mla-kv-cap/) for the method and scripts.

### Why this is a new ticket and not part of W12

W12 changed the estimator. Changing memory headroom in the same session would have
mixed two variables against a baseline that had just moved. The ladder in W12 is that
baseline; this ticket measures against it.

### The three levers

**A. Raise Apple's Metal working-set cap.** `sudo sysctl iogpu.wired_limit_mb=57344`
(56 GB). W12 **reopened this**: it was declined in the original grilling partly because
it "does not fix the over-count", and the over-count is now fixed, so the Metal cap is
the literal binding ceiling. It is still a system-wide change the user must make and
re-apply after a reboot. oMLX's own log suggests 62259 (62 GB), which would leave ~2 GB
for macOS on this box — 56 GB is the number `CLAUDE.md` already records.

**B. Shrink the in-RAM hot KV tier.** At the 45,072 failure the process held ~36 GB:
~23 GB of model plus a ~10.3 GB pool. `OMLX_HOT_CACHE` is 8 GB today. Cutting it trades
warm restores in RAM for prefill headroom — and unlike W5's test of the same lever,
which ran under the 7x over-count and proved nothing about the transient, this would be
measured against an honest estimate. It is one env var and it affects **all three**
profiles, so the cost lands on Bonsai and Muse too.

**C. Serve GLM from the 4-bit quant.** `lmstudio-community/GLM-4.7-Flash-MLX-4bit`,
**15.70 GB** against the 6-bit's 22.67 GB. The freed ~7 GB attacks the transient
ceiling directly, since the transient is charged on top of resident weight. The user
reopened this during W12's grilling, so it is permitted. It costs a 15.70 GB download,
an unmeasured capability drop on the **default** profile, and a repeat of W5's serve
check. W13 §4 already ruled a re-quant of a roster model in scope.

### What makes this a judgement call

- **The levers are not additive in any obvious way.** A and C both buy roughly
  "5–7 GB", but the transient grows with total sequence length, so buying 7 GB does not
  buy proportional context. W12 measured 1.25x the tokens costing 2.3x the time.
- **A bigger declared window may not be worth its door charge.** 40,976 tokens already
  costs 266 s cold, and W13 established that TTFT gates the **default** profile. A
  window nobody can afford to fill is not a win.
- **B and C tax something real.** B costs every profile its RAM cache tier; C costs the
  default profile unmeasured capability.
- **The edge is a race, not a wall.** 40,960 passes only because the adaptive throttle
  evicts and resumes in time. More headroom may widen the race rather than remove it,
  which would show up as intermittent failures — the worst kind.

### Decide as well

- Whether the guard's **under-pricing of the prefill peak** should be reported upstream
  or patched too. W12 measured `KV+SDPA 1.55 GB` quoted for a step whose real transient
  exceeded 14 GB. The `max_context_window` rail makes it harmless today by never
  letting an oversized prompt reach admission, but the mispricing is still there.
- Whether any raised number changes the **rail** (declared + 4,096) that W12 set.

### Acceptance

A decision on A, B and C with reasoning, and — if any is taken — a re-run of W12's
ladder proving the new number, measured the same way: fresh nonce per rung,
`max_tokens: 1`, zero `Embedding:` lines, one server process, warm-up already paid.

## Resolution

**No lever is taken. GLM keeps 32,768 and the 36,864 rail, and nothing in the tree
changes.** The ticket asked whether more memory headroom buys GLM more context. It does
not, because **memory is not what binds**. The user waits at most **120 s** for a cold
open of one long file, and prefill cost grows as O(n²), so the time budget caps the
context long before the Metal cap does.

No ladder was run, and none was owed: the acceptance clause requires one only if a lever
is taken. The decision rests on two rungs W12 already measured, which bracket the limit
on both sides. Method, arithmetic and the written upstream report are in
[assets/w17-prefill-headroom](../assets/w17-prefill-headroom/).

| Lever | Verdict | Because |
|---|---|---|
| **A** raise `iogpu.wired_limit_mb` | **Declined** | +4.16 GiB of a ceiling nothing reaches, against a real reboot-recovery risk |
| **B** shrink `OMLX_HOT_CACHE` | **Declined** | cannot buy cold headroom at all — the ticket's premise was wrong |
| **C** 4-bit re-quant | **Declined** | attacks a constraint that does not bind inside the budget |
| Guard under-pricing | **Report, do not patch** | the rail already neutralises it; a second source patch is debt |

### 1. The binding constraint is the user's patience, not the Metal cap

W12's ladder brackets 120 s on both sides with measured points:

| Cold prompt | Time | Against a 120 s budget |
|---|---|---|
| 32,783 | **116.00 s** | inside, 4 s to spare |
| 40,976 | **266.09 s** | 2.2× over |

Fitting `t = a·n + b·n²` to the two rungs *below* the throttle (10,256 → 18.83 s;
24,592 → 75.17 s) gives `a = 9.63e-4`, `b = 8.51e-8`. Tested on the two rungs the fit
never saw:

| Prompt | Predicted | Measured | Ratio |
|---|---|---|---|
| 32,783 | 123.1 s | 116.0 s | **0.94×** — natural rate |
| 40,976 | 182.4 s | 266.1 s | **1.46×** — throttle |

So **the prefill throttle turns on between 32,783 and 40,976 tokens**. Below the
declared cap GLM already runs at its natural rate, and a memory lever has no throttle to
remove. Solving the fit for 120 s gives **~32,311 tokens**: W12 declared **32,768** on
memory grounds and landed within **1.5 %** of the time boundary by accident.

Even with infinite memory, 45,000 tokens costs ~216 s at the natural rate.

### 2. The ticket's memory arithmetic was wrong in three places

Read from `omlx/process_memory_enforcer.py`; the abort limit is
`min(static_ceiling, metal_cap) − hot_cache_reservation`.

- **`--memory-guard-gb 48` does not set the abort limit.** It sets the *dynamic*
  ceiling, which drives the 40.8 / 45.6 GB watermarks. The abort uses
  `min(static, metal)` only — which is why W12 saw the process reach 50.3 GB rather
  than stop at 48. Static is 62 GiB here (64 − 2, `custom` tier); metal is **51.84 GiB**
  (`max_recommended_working_set_size` = 55,662,788,608 B, sysctl unset).
- **Lever B cannot buy cold headroom.** `hot_cache_reservation` is
  `min(hot_cache_max, hot_cache_used + 512 MiB)` — it tracks *use*, not the 8 GB cap.
  During W12's cold ladder the tier held ~1 GiB, so the reservation was ~1.5 GiB:
  51.84 − 1.5 = **50.3**, exactly the abort figure in the log. Cutting the cap to 2 GB
  would have bought nothing. B is a **variance** lever — it limits how far the ceiling
  falls once the tier fills mid-session, which is the mechanism behind W5's "safe when
  fresh is not safe mid-session". Kept at 8 GB: W7 found the default writes nothing to
  the SSD tier, so this roster rarely fills the hot tier.
- **Lever A buys +4.16 GiB, not "5–7 GB"** — and it switches on
  `mx.set_wired_limit(56 GiB)`, which oMLX deliberately skips while the sysctl is unset
  (`:239`). Its own comment cites issue #2184: a jetsammed process strands its wired
  allocation at kernel level until reboot.

### 3. Memory was never close on any prompt the user would send

Peak RSS from W12's own sampler, against the 51.84 GiB cap: **23.2 / 26.1 / 27.9 /
24.7 GB** on the passing rungs. Note 24,592 peaked **higher** than 40,976 — that
inversion is the throttle evicting buffers to hold the process down, and it is why the
larger prompt reads lower and costs 84 s more.

This is why lever A was re-opened after being approved mid-grilling, and then declined:
it was recommended as margin, and the measurements say there is no case to insure. The
one prompt that did reach 50.3 GB is now rejected by W12's rail in 1.67 s.

**Caveat**: the sampler read RSS; oMLX prices itself on `phys_footprint`, which counts
Metal pages RSS can miss, so those peaks under-read.

### 4. Lever C was verified before it was declined

`lmstudio-community/GLM-4.7-Flash-MLX-4bit`, read from the Hugging Face API: **16.87 GB
/ 15.71 GiB**, 4 shards, flat affine 4-bit `group_size` 64, same `glm4_moe_lite`, same
`kv_lora_rank` 512 / `qk_rope_head_dim` 64 (so `patch-omlx-mla-kv.mjs` still applies),
same three `eos_token_id`s (so W9's LM Studio stop list still applies). Disk has 63 GiB
free, so it fits. It is a clean drop-in, declined because ~6.2 GiB of freed weight
attacks a ceiling that §1 and §3 show does not bind.

### 5. GLM 4.7 Flash has no custom kernel — the map's last kernel question is closed

`glm_moe_dsa` is registered in `NATIVE_KERNEL_PACKAGES` but binds to
`model_type == "glm_moe_dsa"` (`oq.py:312`, `:3864`, `:6882`) — GLM-5.2 with DeepSeek
sparse attention. This roster's GLM is **`glm4_moe_lite`**, a different model type. Its
sources are decode-shaped anyway (`dsa_indexer`, `dspark_qmv`, `sparse_mla`). There is
no prefill kernel to build for this model, and building the package changes nothing for
this roster.

### 6. Switching profile is not a workaround

GLM is the fastest prefiller on the roster, by roughly 2.7×. Two-minute door charges:

| Profile | Tokens in 120 s cold |
|---|---|
| GLM 4.7 Flash (`--glm`) | **~32,300** |
| Muse Glimmer (bare `ai`, default) | ~22,800 |

Muse's figure is **indicative only** — two measured points, no test rung, and the 65,536
rung may itself be throttled, which would inflate `b`. The conclusion survives the
caveat: **no profile on this box opens a 45,000-token file in two minutes**, and `--glm`
is already the right profile for the long-file case at its already-boundary cap.

### 7. The under-priced prefill peak: reported, not patched

`_admission_estimate` (`scheduler.py:8833`) charges the transient of a **floor-size**
chunk (`_prefill_min_chunk_tokens`, 256), but prefill *starts* at `prefill_step_size`
(2048) and only shrinks once the throttle engages. On a cold server no floor-size sample
exists and the throttle has never run, so admission uses the throttled steady state — a
**lower** bound on the peak — as if it were an upper bound. That is the whole defect, and
`_prefill_speed_priority` already takes the correct branch for the un-throttled regime.

Not patched: constraint 5 wants one build upgraded in place, the repo already carries one
source patch, and the `max_context_window` rail already converts the five-minute abort
into a 1.67 s HTTP 400. The report is written and ready to file at
[assets/w17-prefill-headroom/upstream-report.md](../assets/w17-prefill-headroom/upstream-report.md)
— **filing it is the user's call.**

### 8. The rail formula survives, with one added rule

The rail stays `declared + 4,096`, which absorbs opencode's tokenizer drift (a prompt
built for 32,768 renders as 32,784). It gains a bound it did not have: the declared
number must satisfy `declared + 4,096 < lowest failing rung`, with a rung of margin.
Today 36,864 sits far below 45,072, so nothing changes. Without the rule, a declared
40,960 would put the rail at 45,056 — one rung below the measured failure and inside its
noise — and the rail would start admitting the aborts it exists to prevent.

### 9. Consequences for the map

- **Constraint 7 is closed for good.** GLM's 32,768 is now justified by **time**, not by
  memory. That reason is stable: it does not move if a future oMLX fixes the guard.
- **W11 must document** that no sysctl is required, and why 32,768 is a time limit.
- **Nothing was measured against long-context capability**, which stays fog.
