# W21 Stage 2 — result: the trimmed suite at ~17.6k tokens

Run 2026-08-13, `omlx 0.5.8.dev3`, port 10082, one model per server run,
`max_tokens: 8192`, no `temperature` sent. Same prompts and same execution graders as
[W14](../w14-capability/README.md) — [`run_long.py`](run_long.py) imports them unchanged and
alters one thing: ~17k tokens of real repository source sit in the system prompt ahead of
the task.

Tables produced by [`report_long.py`](report_long.py), whose selftest reproduces W14's
published recovery counts (GLM 0, Muse 2, Bonsai 3) from the stored runs before printing
anything.

## Verdicts

| Model | Context | T1 | T2 | T4 | pass@1 | pass@≤2 |
|---|---|---|---|---|---|---|
| Muse Glimmer | ~4k | `1 1 1` | `1 1 1` | `1 1 1` | 9/9 | 9/9 |
| **Muse Glimmer** | **~17.6k** | `F 1 1` | `1 1 1` | `1 1 1` | **8/9** | **8/9** |
| GLM 4.7 Flash | ~4k | `1 1 1` | `1 1 P` | `F 1 P` | 6/9 | 6/9 |
| **GLM 4.7 Flash** | **~17.6k** | `1 2 1` | `1 F F` | `1 1 1` | **6/9** | **7/9** |
| Ternary Bonsai | ~4k | `1 1 1` | `1 P 2` | `2 2 1` | 5/9 | 8/9 |
| **Ternary Bonsai** | **~17.6k** | `1 1 1` | `1 1 F` | `1 2 1` | **7/9** | **8/9** |

Every model stayed inside GLM's real client budget: peak prompts 17,406 / 17,637 / 18,679
against the 24,576 ceiling (32,768 context − 8,192 reserved output).

### The headline: Muse's lead does not survive, and nobody takes it

At 4k on these three tasks the pass@1 spread was **9 / 6 / 5**. At 17.6k it is **8 / 6 / 7**.
Muse loses one and Bonsai gains two, so a **4-point lead becomes 1 point** — inside the
noise band W14 declares for a suite this size. On pass@≤2 Muse and Bonsai **tie at 8/9**.

**The three models are not separable at this context length by this suite.** That is the
result. It is not that the ranking inverted; it is that the ranking dissolved.

### The pre-registered floor, applied

Both rules were fixed in [README.md](README.md) before Stage 1 ran:

1. **Margin** — a challenger must solve **at least 3 more** task-runs than Muse. Best
   challenger is Bonsai at 8, level with Muse's 8. **Does not fire.**
2. **Collapse** — Muse solving under half while a challenger leads. Muse solved 8 of 9.
   **Does not fire.**

**Muse Glimmer keeps bare `ai`.** The rule is applied as written, not re-read after the
numbers arrived — and it is worth being plain that the rule is what holds the default here,
not the evidence. The evidence at the context this repo actually runs is a tie.

## Cost, like for like

The 4k column is recomputed from W14's stored per-run timings **over the same three tasks**,
so the only variable is context length.

| Model | 4k wall | 4k solved | 4k min/solved | 17.6k wall | 17.6k solved | 17.6k min/solved | Degradation |
|---|---|---|---|---|---|---|---|
| Muse Glimmer | 20.6 min | 9/9 | 2.29 | 25.5 min | 8/9 | 3.19 | 1.39× |
| GLM 4.7 Flash | 12.6 min | 6/9 | 2.10 | 25.5 min | 7/9 | **3.64** | **1.73×** |
| Ternary Bonsai | 16.5 min | 8/9 | 2.07 | 18.5 min | 8/9 | **2.31** | **1.12×** |

**Ternary Bonsai is the cheapest model per solved task at this context, by a clear margin,
and it degrades least.** GLM degrades most — the reverse of what its prefill advantage
predicts, because prefill is paid once and decode is paid on every token.

### A caveat that limits how far this table reaches

At 4k the three min/solved figures are **2.07, 2.10, 2.29 — effectively tied**, which is not
what [W18](../../tickets/18-default-after-capability.md) reported (Muse 3.46, GLM 3.83,
Bonsai 4.09). The difference is the suite: W18 used all four tasks, and **T3 is where GLM's
runaways lived**. Dropping T3 removes GLM's largest cost, so the trimmed suite flatters GLM
and Bonsai against W18's ranking.

So this table may be read **down its columns** (4k against 17.6k, same tasks) but **not
against W18's numbers**. W18's ranking is not reproduced here and is not challenged here.

## Two measurements that correct the map

### 1. Every decode rate in the roster table is a short-context number

Read from the server's own completion lines, across both stages:

| Model | `CLAUDE.md` roster | ~17.6k (Stage 2) | ~22k (Stage 1) | Ratio at 22k |
|---|---|---|---|---|
| Muse Glimmer | 26 tok/s | 10.7–16.6 | 7.9–11.3 | ~0.38× |
| GLM 4.7 Flash | 68 tok/s | 19.8–26.2 | 21.9–24.1 | ~0.34× |
| Ternary Bonsai | 38 tok/s | — | 9.8–14.3 | ~0.32× |

**All three lose about two-thirds of their decode rate** between a short prompt and an
agentic one. The roster's 26 / 68 / 38 become roughly **11 / 23 / 12.5** at the context this
repo's agent loop actually runs.

**GLM keeps its relative lead** — at 22k it still decodes about 2× Muse — so the `--glm`
profile's rationale is unaffected. What changes is every absolute per-turn cost estimate on
the map, because decode dominates a turn once the door charge is paid.

### 2. `cached_tokens` does not round to 2048 on every model

[W13](../w13-prefix-extension/README.md) measured the paged cache rounding down to a
2048-token block, on Bonsai, and `CLAUDE.md` carries it as a general rule. Stage 1 shows it
is model-dependent:

| Model | `cached_tokens` observed | Block | Fresh tokens re-prefilled per turn |
|---|---|---|---|
| Muse Glimmer | 20,480 | 2,048 | 1,236–1,259 |
| Ternary Bonsai | 22,528 | 2,048 | 800–823 |
| **GLM 4.7 Flash** | 21,760 / 22,016 | **256** | **9–289** |

The documented rule understates GLM's cache by a factor of eight.

## Behaviour worth recording

- **Muse's only long-context loss is T1, the tool chain** — the task it swept at 4k, and the
  one that most resembles this repo's agent loop. One run of three, so noise cannot be ruled
  out, but the loss is not spread across the suite.
- **GLM's runaways vanished**: 2 protocol failures at 4k on these tasks, **0** at 17.6k. Its
  T4 went `F 1 P` to a clean sweep. Its T2 went the other way, `1 1 P` to `1 F F`.
- **GLM still never recovers from real failure output.** 2 repair turns carrying real output,
  0 recoveries — W14's finding reproduced at long context. Its one `pass@2` is on **T1**,
  whose repair turn carries a **hand-written hint**, not execution output. In W14 no model
  ever needed a T1 repair, so that record was built entirely on T2/T3/T4. The distinction is
  kept in the tables and must not be collapsed.
- **Bonsai recovered once from real output** and remains the model that takes feedback best.

## One contaminated measurement, found and repaired

**The Mac slept for 75.1 minutes in the middle of GLM's run.**

```
12:40:56  Sleep — Entering Sleep state due to 'Clamshell Sleep'
```

The lid closed 76 seconds after GLM's T2[2] first attempt finished, followed by maintenance
sleeps until 13:57. GLM's `T2_merge_module[2]` was recorded at **5,057 s**; the server log is
silent across the whole window, because the server was suspended rather than slow.

- **Verdicts are unaffected.** The model generated normally on both sides of the gap — 4,669
  tokens in 220.75 s, then 7,294 in 330.96 s, both at its ordinary ~21 tok/s — and failed the
  tests on merit.
- **Wall-clock was repaired** by subtracting the measured sleep from the run window:
  100.6 → **25.5 min**. Sleep windows were read from `pmset -g log` and intersected with each
  model's server-log window.
- **Muse (11:58–12:24) and Bonsai (14:04–14:23) overlapped no sleep at all** and needed no
  correction. `caffeinate -i -m -s` was armed after the discovery, before Bonsai ran.

Recorded rather than re-run, because the repair is exact and the verdicts never depended on
it. **A future measurement on this box should arm `caffeinate` before it starts** —
and note that `caffeinate` cannot override clamshell sleep.

## Limits

- **9 runs per model, 3 tasks.** A gap of one or two is noise, and the whole result here is
  gaps of one or two. This suite can say the models are indistinguishable at 17.6k; it cannot
  rank them.
- **~17.6k, not a full window.** Sized to leave the multi-turn conversation room inside
  GLM's real 32,768 budget with 8,192 output reserved. Nothing here measures 32k or 65k.
- **T3 is absent**, so this cannot be compared to W18's four-task metric — see the caveat
  above.
- **One task set, one author, one run.** A decision aid, not a benchmark.
