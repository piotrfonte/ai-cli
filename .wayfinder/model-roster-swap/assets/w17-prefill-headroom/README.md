# W17 asset — why no memory lever buys GLM usable context

Analysis that resolved
[Buy prefill headroom for GLM — Metal cap, hot-cache size and the 4-bit re-quant](../../tickets/17-glm-prefill-headroom.md).

## The question

W12 fixed a 7.08x KV over-count and still could not reach 65,536 tokens, because the
binding constraint turned out to be the prefill activation transient against Apple's
Metal cap. W17 asks whether three levers — a raised Metal cap, a smaller hot KV tier,
or a 4-bit re-quant — buy back the window.

**They do not, and the reason is not memory.** A time budget caps the context long
before memory does.

## Method

No server was started and no request was sent. Every number here comes from
measurements already on the map, from oMLX's own source, or from Hugging Face's
model index. That is deliberate: the decision rests on two rungs W12 already
measured, which bracket the user's stated limit on both sides.

- `fit-prefill-curve.py` — fits `t = a*n + b*n^2` and solves it for a time budget.
- `upstream-report.md` — the bug report for oMLX, written but not filed.

## 1. The user's limit is two minutes, and it binds before memory

The user opens one long file, cold, and waits at most **120 s** for the first token.
W12's ladder brackets that on both sides with measured points:

| Cold prompt | Time | Verdict against a 120 s budget |
|---|---|---|
| 32,783 | **116.00 s** | inside, with 4 s to spare |
| 40,976 | **266.09 s** | 2.2x over |

No fit is needed for the decision. Both points are measured, and both sit on the
correct side of the answer.

## 2. The fit says the throttle never engages inside the budget

`t = a*n + b*n^2` fitted to the two rungs **below** the throttle, then tested on the
two rungs the fit never saw:

```
a = 9.6272e-04 s/token      b = 8.5148e-08 s/token^2

    prompt   predicted    measured    ratio
    32,783      123.1 s      116.0 s    0.94x   <- natural rate
    40,976      182.4 s      266.1 s    1.46x   <- throttle
```

So the prefill throttle turns on **between 32,783 and 40,976 tokens**. Below the
declared cap GLM already runs at its natural rate, and a lever that adds memory has
no throttle to remove. Above it, the penalty is 46 % — real, but on prompts that cost
182 s even with the throttle gone.

Solving the fit for 120 s gives **~32,311 tokens**. W12 declared **32,768** on memory
grounds and landed within **1.5 %** of the time boundary by accident.

Even with infinite memory, 45,000 tokens costs ~216 s at the natural rate.

## 3. Memory was never close on any prompt the user would send

Peak RSS sampled by W12's own script, against a 51.84 GiB Metal cap:

| Prompt | Peak RSS | Result |
|---|---|---|
| 24,592 | 27.91 GB | OK |
| 32,783 | 26.06 GB | OK |
| 40,976 | 24.69 GB | OK |
| 40,975 (+4,096 out) | 26.99 GB | OK |

Note the **inversion**: 24,592 peaked higher than 40,976. That is the throttle
evicting pooled buffers to hold the process down, which is why the larger prompt
reads lower and costs 84 s more.

**Caveat.** The script sampled RSS; oMLX prices itself on `phys_footprint`, which
counts Metal pages RSS can miss. These peaks therefore under-read, and the one prompt
that did reach 50.3 GB (45,072 tokens) is now rejected by W12's rail in 1.67 s.

## 4. The memory arithmetic the ticket got wrong

Read from `omlx/process_memory_enforcer.py` on the pinned build.

```
metal_cap      = iogpu.wired_limit_mb if set, else max_recommended_working_set_size
static_ceiling = system_RAM - tier_reserve
abort_limit    = min(static_ceiling, metal_cap) - hot_cache_reservation
hot_cache_reservation = min(hot_cache_max, hot_cache_used + 512 MiB)
```

On this box: `max_recommended_working_set_size` = 55,662,788,608 B = **51.84 GiB**;
`iogpu.wired_limit_mb` = **0** (unset); tier is `custom` with a **2 GiB** reserve, so
`static_ceiling` = 62 GiB. The abort limit is therefore **51.84 GiB** minus the hot
reservation.

Three corrections follow:

1. **`--memory-guard-gb 48` does not set the abort limit.** It sets the *dynamic*
   ceiling, which drives the soft and hard watermarks (40.8 / 45.6 GB in W12's log).
   The abort uses `min(static, metal)` only. That is why W12 saw the process reach
   50.3 GB rather than stop at 48.
2. **Lever B cannot buy cold headroom.** The hot-cache reservation tracks *use*, not
   the configured maximum. During W12's cold ladder the tier held about 1 GiB, so the
   reservation was ~1.5 GiB against an 8 GB cap — 51.84 − 1.5 = 50.3, exactly the
   abort figure in the log. Cutting the cap to 2 GB would have bought nothing at that
   moment. B is a **variance** lever: it limits how far the ceiling falls once the
   tier fills mid-session, which is the mechanism behind W5's "safe when fresh is not
   safe mid-session".
3. **Lever A buys +4.16 GiB, not the "5–7 GB" the ticket estimated** — and it has a
   side effect. With the sysctl set, oMLX calls `mx.set_wired_limit(56 GiB)`
   (`:498`, `:282`), which it deliberately skips while the sysctl is unset (`:239`).
   Its own comment cites issue #2184: a jetsammed process strands its wired
   allocation at kernel level until reboot.

## 5. Lever C verified, then declined

`lmstudio-community/GLM-4.7-Flash-MLX-4bit`, read from the Hugging Face API:

- **16.87 GB / 15.71 GiB**, 4 shards, flat affine 4-bit, `group_size` 64.
- Same `model_type: glm4_moe_lite`, same `kv_lora_rank` 512 and `qk_rope_head_dim` 64,
  so `scripts/patch-omlx-mla-kv.mjs` would still apply unchanged.
- Same three `eos_token_id`s (154820 / 154827 / 154829), so W9's LM Studio stop list
  would still apply.

It is a clean drop-in and it was declined anyway: ~6.2 GiB of freed resident weight
attacks a ceiling that sections 2 and 3 show does not bind inside the budget.

## 6. GLM 4.7 Flash has no custom kernel — settled

The map carried `glm_moe_dsa._ext` as "untouched and still unexamined". Examined:

- `omlx/custom_kernels/__init__.py` lists `NATIVE_KERNEL_PACKAGES = ("bonsai",
  "glm_moe_dsa", "minimax_m3", "qwen35_prefill")`.
- The package binds to `model_type == "glm_moe_dsa"` (`oq.py:312`, `:3864`, `:6882`)
  — GLM-5.2 with DeepSeek sparse attention. This roster's GLM is **`glm4_moe_lite`**,
  a different model type.
- Its sources are decode-shaped anyway: `dsa_indexer`, `dspark_qmv` (quantized
  matrix-**vector**), `sparse_mla`, `deepseek_v4_sparse_attention`.

So there is no prefill kernel to build for this model, and building the package would
change nothing for this roster.

## 7. No profile on this roster opens a 45,000-token file in two minutes

GLM is the fastest prefiller here, at roughly 2.7x the other two. Fitting Muse
Glimmer's two measured points (12,882 in 64.5 s; 65,536 in 414 s):

| Profile | Two-minute door charge |
|---|---|
| GLM 4.7 Flash (`--glm`) | ~32,300 tokens |
| Muse Glimmer (bare `ai`, default) | ~22,800 tokens |

**Muse's figure is indicative only** — two points, no test rung, and the 65,536 rung
may itself be throttled, which would inflate `b` and make the figure pessimistic.

The useful conclusion holds regardless: switching profile is not a workaround, and
`--glm` is already the right profile for the long-file case. Its declared 32,768 is
already at the boundary.
