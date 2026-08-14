# W12 asset — GLM 4.7 Flash's real context ceiling

Measurement that resolved
[Decide GLM's context cap against oMLX's 7x MLA over-count](../../tickets/12-glm-context-cap.md).

## The question

W5 found oMLX charging GLM 4.7 Flash **~374 KB/token** of KV against a real **52.9**,
and rejecting a 65,536-token prompt in 5.1 s. The ticket asked whether to correct the
estimate or live with a low cap.

## Method

`omlx 0.5.8.dev3` + `scripts/patch-omlx-mla-kv.mjs`, ai.sh's flags (hot 8 GB, SSD
≤25 GB, guard 48, concurrency 2), MCP-free. Prompt sizes are cut with the model's own
tokenizer, so `prompt_tokens` lands on the target instead of near it.

**Every probe uses `max_tokens: 1` unless it is a serve gate**, so wall time is prefill
alone. Never subtract decode from the server log line — oMLX builds report `tok/s`
differently.

**Each rung carries its own nonce**, so nothing is served from the prefix cache and
every rung is a genuine cold *door charge* — the worst case, and the one a declared
context cap has to survive.

- `measure-context-ceiling.py` — W5's ladder re-run, plus a warm-up rung and a serve
  gate. Records swap at start and end.
- `find-real-ceiling.py` — probes downward from the optimistic end until one rung
  holds, sampling the server's RSS throughout, then runs a serve gate at that size.

Reproduce with the server up on port 10081:

```bash
python3 find-real-ceiling.py "$(date +%s)"
```

## Three runs were discarded before any number here was trusted

1. **Embedding contamination.** The first run's server log carried 5 `Embedding:`
   lines and two foreign chat completions from a live opencode session. W5 §7
   discarded a run for exactly this; the rule is zero.
2. **A stale server.** A second oMLX server survived an earlier `kill`, so two copies
   of a 23 GB model were resident. The box went **16 GB into swap** and prefill read
   132 tok/s. After cleanup the same prompt read 545 tok/s.
3. **Cold warm-up read as the rate.** W5 warned the first large prefill after a model
   load costs about twice the steady rate. `measure-context-ceiling.py` now spends a
   10k-token warm-up rung it does not report.

Every number below comes from a log with zero `Embedding:` lines, one server process,
and a warm-up already paid.

## Result

| Cold prompt | Result | Time | Rate |
|---|---|---|---|
| 10,256 | OK (warm-up) | 18.83 s | 545 tok/s |
| 24,592 | OK | 75.17 s | 327 tok/s |
| 32,783 | OK | 116.00 s | 283 tok/s |
| 40,976 | OK | 266.09 s | 154 tok/s |
| 40,975 (+4,096 out) | OK — `stop`, `SERVE OK` | 319.73 s | — |
| 45,072 | **FAILS** | ~5 min lost | — |

**The over-count was wrong about the reason and accidentally right about the answer.**
Correcting KV from ~374 to 52.9 KB/token drops the charge at 65 k from 23.41 GB to
3.30 GB, and the server now logs `Estimated memory per 64-token block: 3.30 MB, KV
override 52.88 KB/tok`. But the binding constraint was never KV. It is the prefill
**activation** transient:

```
Memory pressure level: ok -> hard (current=48.1GB, soft=40.8GB, hard=45.6GB)
Prefill force-stopped at 20608 tokens: memory 50.3GB exceeds physical cap 50.3GB
Unloading model: GLM-4.7-Flash-MLX-6bit (immediate abort)   freed=36.13GB
```

So the guard now **under**-prices the peak it admits — it quoted `KV+SDPA 1.55 GB` for
a step whose real transient was over 14 GB. The inflated KV had been masking that.

**40,960 passes only because the adaptive throttle wins a race.** The server pauses the
request, evicts pooled Metal buffers, and resumes at a smaller chunk. At 45,072 the
prefill reaches the physical cap before the throttle reacts. Numbers near that edge are
therefore not reliably repeatable, which is why the declared cap sits well below it.

**Cost grows far faster than length**: 1.25x the tokens from 32,783 to 40,976 costs
2.3x the time.

## What was declared

| Setting | Value | Job |
|---|---|---|
| `limit.context` (opencode.json, W9) | **32,768** | the client's budget |
| `max_context_window` (model_settings.json) | **36,864** | safety rail |

They are deliberately **not** equal. Mirroring them was tried and failed: a prompt built
for 32,768 rendered as 32,784 tokens and was hard-rejected. One 4,096-token block of
headroom absorbs that drift while still stopping the overruns the rail exists for.

Verified after the change: 45,072 tokens → clean HTTP 400 in **1.67 s** (against ~5
minutes and a model unload before); 32,784 tokens → serves, `finish_reason: stop`,
`SERVE OK`, 96.79 s.
