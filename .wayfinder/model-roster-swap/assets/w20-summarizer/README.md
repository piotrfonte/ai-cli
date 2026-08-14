# W20 — the summarizer model, measured

**Question.** Which model runs opencode-mem's auto-capture summarizer, now that
W18 made the default a 26 tok/s model?

**Answer.** The session's own model (option A) — the arrangement already in
place — but only after raising the plugin's abort. On the settings that shipped,
auto-capture on the default was **broken, not slow**: every capture exceeded the
30 s per-iteration abort, so nothing was ever saved.

## Files

| File | What it does |
|---|---|
| `summarizer.py` | A faithful replay of one auto-capture request. Every field copied from the installed plugin |
| `sweep.py` | M1 — Gate 0: capture wall vs the abort, swept across input sizes |
| `contend.py` | M2/M3/M4 — Gate 1: what a capture in flight costs the turn that lands on it |
| `server.sh` | oMLX lifecycle on port 10082, same flags as `ai.sh` |
| `sample-footprint.sh` | Gate 2 — samples `phys_footprint`, because `ps` RSS under-reads MLX |
| `results-*.json` | Raw runs |

## The floor, fixed before the run

Per W19. Gate 1's threshold was chosen by the user; the others are preconditions.

- **Gate 0** — a capture must return a parsed `save_memory` call inside the
  plugin's per-iteration abort.
- **Gate 1** — a coding turn starting while a capture runs keeps **≥ 75 %** of
  its solo decode rate, and does not error.
- **Gate 2** — no eviction, no `507`, peak under the guard's **40.8 GB** soft
  target.

## What the plugin actually sends — read from source, before measuring

Three facts the ticket did not have, each of which changed the question.

1. **A capture never overlaps the turn that produced it.** It fires on
   `session.idle` plus a **10 s debounce** (`index.js:411`). It overlaps the
   **next** turn — so *capture duration*, not capture cost, is what decides this.
2. **Each iteration aborts at 30 s.** `autoCaptureIterationTimeout` defaults to
   `30000`; the shipped `opencode-mem.jsonc` did not set it.
3. **No `max_tokens` is sent.** oMLX applied its own default — confirmed in the
   log as `request_max_tokens=None, max_tokens=32768`.

### A harness trap worth recording

`urlopen(timeout=)` is a **per-socket-read** timeout; the plugin's
`AbortController` is a **total** deadline. The first version scored a 72 s
request as passing a 30 s budget. Gate 0 must be judged on the wall, not on a
socket timeout.

## Gate 0 — the capture must finish (solo, 2 repeats per size)

Wall in seconds. **Bold fails the 30 s abort.**

| Input chars | Muse Glimmer | Ternary Bonsai | GLM 4.7 Flash |
|---|---|---|---|
| 24,000 | **45.9 / 44.3** | **71.8 / 30.8** | 21.3* / 11.5 |
| 12,000 | **43.0 / 30.4** | **41.8** / 20.6 | 14.2 / 12.4 |
| 6,000 | **52.3 / 50.0** | **30.3** / 17.5 | 16.0 / 9.6 |
| 2,000 | **76.4 / 69.1** | 25.3 / 27.3 | 9.4 / 8.6 |
| **Passes** | **0 / 8** | 4 / 8 | 7 / 8 |

\* GLM's one miss was **not** a timeout: `finish_reason: stop`, zero tool calls,
596 chars of prose instead. A protocol failure, which the iteration loop retries.

### Shrinking the input makes Muse *slower*

The single most useful result here, because it kills the obvious fix. Prefill
falls exactly as expected — 7,494 → 1,260 prompt tokens — and the wall **rises**,
because the model reasons more when given less to work from:

| Input chars | Prompt tokens | Completion tokens | Wall |
|---|---|---|---|
| 24,000 | 7,494 | 1,009 | 45.9 s |
| 2,000 | 1,260 | 1,203 | 76.4 s |

The abort is **decode-bound**. At 26 tok/s, ~1,000 output tokens is ~38 s on its
own, so no input size fits a 30 s budget. A 440-char probe — a near-empty
context — still took **24.7 s**.

Prefill also amortises and decode does not: the 24,000-char runs were **6,144 of
7,494 tokens cached** and still failed.

**Corollary: option C (fewer iterations) cannot help.** Iterations only matter
once iteration 1 succeeds, and iteration 1 is what exceeds the budget — and
iteration 2 sends *more*, because the loop appends.

## Gate 1 — what a capture costs the next turn

Coding turn: 13,165-token prompt, `max_tokens: 2048`, warm prefix (12,288 cached)
in both arms, so contention is the only variable. The first attempt compared a
**cold** control against a **warm** contended run and was discarded.

| Summarizer | Retained | Verdict |
|---|---|---|
| Muse (same model) | 76.7 %, 81.1 % | **PASS** |
| Ternary Bonsai | 73.5 %, 72.4 %, 72.5 % | FAIL |
| GLM 4.7 Flash | 68.4 % | FAIL |

**Sharing one model is cheaper than adding a second.** Two models run two forward
passes; one model shares a single batched pass. This inverts the ticket's
assumption that a small second model would be the light-touch option.

**Honesty about the margin.** The control varied 16.6–20.9 tok/s end-to-end
across runs (±13 %). Each ratio pairs its own control, which absorbs most of that
drift, but Muse (mean 78.9 %) and Bonsai (mean 72.8 %) are separated by ~6 points
at n=2 and n=3, straddling the 75 % line. The Bonsai result is a consistent
near-miss, not a decisive one. It did not decide the ticket alone.

## Gate 2 — memory

| Resident | Peak `phys_footprint` | Eviction |
|---|---|---|
| Muse alone | ~19 GB | none |
| Muse + Bonsai | 33 GB | none |
| Muse + GLM | **44 GB** | **ping-pong** |

Muse + GLM reproduces the thrash the model override exists to prevent:

```
Evicting 'Muse-Glimmer-30B-4bit' to fit 'GLM-4.7-Flash-MLX-6bit'
  under the admission soft target (43.41GB > 40.80GB)
Unloading model: Muse-Glimmer-30B-4bit (immediate abort)
Admitting 'Muse-Glimmer-30B-4bit' above the admission soft target with
  no idle model left to evict (43.42GB > 40.80GB, ceiling 48.00GB)
Evicting model 'GLM-4.7-Flash-MLX-6bit' (pressure=soft)
```

### `ps` RSS under-reads MLX by 1.66×

W17 flagged this as a caveat; here is the number. With two models resident:

| Measure | Reading |
|---|---|
| `ps -o rss` | 18.64 GB |
| `phys_footprint` | **31 GB** (peak 33 GB) |
| of which `IOAccelerator (graphics)` | 27.1 GB |

Use `footprint -p <pid>` or `vmmap -summary`. A guard threshold checked against
RSS is checked against the wrong number.

**One correction to an early reading of the log.** `MemoryMonitor initialized
(estimator-only, eviction disabled)` is a **per-engine** line and does not mean
the server will not evict — `engine_pool` and `process_memory_enforcer` both
evict, as the trace above shows.

## The decision

Every option failed some gate as configured. Option A was the only one passing
Gates 1 and 2, and its Gate 0 failure was purely the 30 s config value — a plugin
config key, not a property of the model. The user chose to raise it and bound the
tail rather than pin a second model or disable capture.

Three settings, applied as one package to `opencode-mem.jsonc`:

| Setting | Was | Now |
|---|---|---|
| `autoCaptureIterationTimeout` | 30,000 (default, unset) | **180,000** |
| `autoCaptureMaxIterations` | 8 | **2** |
| `memoryExtraParams` | unset | **`{"max_tokens": 2048}`** |

`max_tokens` is not in the provider's `PROTECTED_KEYS`, so `memoryExtraParams` is
spread verbatim into the body — a supported lever, not a fourth patch. 2048 and
not lower: captures emit 689–1,203 completion tokens, and a truncating cap yields
`finish_reason: length` with no tool call, which is a silently failed capture.

### Verified after the change

Three consecutive full-size captures on Muse, warm:

| Run | Wall | Finish | Completion tokens | Tool call |
|---|---|---|---|---|
| 1 | 44.64 s | `tool_calls` | 965 | `save_memory` |
| 2 | 49.57 s | `tool_calls` | 1,060 | `save_memory` |
| 3 | 38.69 s | `tool_calls` | 758 | `save_memory` |

`request_max_tokens=2048` confirmed in the server log, so the 32,768 ceiling is
closed. The plugin's own loader resolves all three values.

## Limits of this measurement

- **One coding-turn shape.** A 13,165-token prompt at `max_tokens: 2048`. A
  shorter turn overlaps a larger fraction of the capture and would retain less.
- **Gate 1 margins are near the noise.** See the honesty note above.
- **A synthetic transcript.** The context is built from this repo's own files, not
  a real captured session; two verification runs judged it `type: "skip"`. That
  affects what the model writes, not how long it takes.
- **`autoCaptureMaxIterations: 2` is reasoned, not measured.** It rests on Muse
  producing a valid tool call on 8 of 8 solo runs. Nothing here measures how often
  a real session needs a second iteration.
