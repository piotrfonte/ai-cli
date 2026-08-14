---
id: W20
title: Decide the summarizer model now the default decodes at 26 tok/s
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: [W18]
---

## Resolution (2026-08-13)

**Option A — the session's own model — and the arrangement does not change. What
changes is the plugin's abort, because on the shipped settings auto-capture was
not costly on the default: it was broken.** Every capture on Muse Glimmer exceeds
the 30 s per-iteration abort, so **0 of 8** completed and nothing was ever saved.
The ticket asked what a capture *costs*; the first measurement showed it never
finishes.

Made, validated, in the tree. Method and raw runs:
[assets/w20-summarizer](../assets/w20-summarizer/).

### The gates

| Summarizer | Gate 0 — finishes in 30 s | Gate 1 — turn keeps ≥ 75 % | Gate 2 — memory |
|---|---|---|---|
| **Muse** (A) | **0 / 8** · 30.4–76.4 s | **PASS** 76.7 %, 81.1 % | PASS · no eviction |
| **Bonsai** (B) | 4 / 8 · fails at the full cap | FAIL 73.5, 72.4, 72.5 % | PASS · 33 GB |
| GLM (not in the options) | 7 / 8 · 8.6–21.3 s | FAIL 68.4 % | **FAIL** 44 GB · ping-pong |

Every option failed some gate. A was the only one clearing Gates 1 and 2, and its
Gate 0 failure is purely a **config value**, not a property of the model.

### Four findings that outrank the ranking

1. **The abort is decode-bound, and shrinking the input makes it worse.** This
   kills the obvious cure and the lever the user first chose. Cutting
   `OPENCODE_MEM_MAX_CONTEXT_CHARS` cuts prefill exactly as expected — 7,494 →
   1,260 prompt tokens — and the wall **rises**, because Muse reasons *more* with
   less context: **44 s at 24,000 chars against 76 s at 2,000**. A 440-char probe
   still cost 24.7 s. Prefill amortises (the 24,000-char runs were 6,144 of 7,494
   tokens cached and still failed); decode never does. **Option C dies with it** —
   iterations cannot rescue a timeout that iteration 1 already blows, and
   iteration 2 sends more, because the loop appends.
2. **Sharing one model is cheaper than adding a small second one** — the reverse
   of the ticket's assumption. Bonsai retains 72–74 % against same-model Muse's
   77–81 %, because two models run two forward passes while one model shares a
   single batched pass. The ticket's memory arithmetic was sound (33 GB measured
   against a predicted ~35 GB, no eviction); it was the *decode* cost that
   disqualified B, which nothing had priced.
3. **The ticket's memory-guard warning was right, and GLM proves it.** Muse + GLM
   reaches a **44 GB** real footprint against the 40.8 GB soft target and
   reproduces the exact thrash `OPENCODE_MEM_MODEL` exists to prevent —
   `Evicting 'Muse-Glimmer-30B-4bit' to fit 'GLM-4.7-Flash-MLX-6bit' … 43.41GB >
   40.80GB`, Muse re-admitted over target, then GLM evicted back under pressure.
4. **The summarizer sent no `max_tokens` at all**, so oMLX applied its own
   **32,768** default (`request_max_tokens=None, max_tokens=32768`) — a 21-minute
   runaway ceiling at 26 tok/s, on a request nobody was watching.

### The change — three settings as one package

`opencode-mem.jsonc`:

| Setting | Was | Now | Why |
|---|---|---|---|
| `autoCaptureIterationTimeout` | 30,000 (default, unset) | **180,000** | Fits the worst measured case: a capture overlapping a turn stretches to 99 s |
| `autoCaptureMaxIterations` | 8 | **2** | At 180 s, 8 iterations is a 24-min tail. Muse called the tool on 8 of 8 solo runs |
| `memoryExtraParams` | unset | **`{"max_tokens": 2048}`** | Closes the 32,768 runaway |

`max_tokens` is not in the provider's `PROTECTED_KEYS`, so `memoryExtraParams` is
spread verbatim into the request body — **a supported config lever, so this needed
no fourth patch**. 2048 and not lower: captures emit 689–1,203 completion tokens,
and a truncating cap yields `finish_reason: length` with no tool call, which is a
silently failed capture.

**Verified after the change**: three consecutive full-size captures on Muse at
**38.69 / 44.64 / 49.57 s**, every one returning a parsed `save_memory` call, with
`request_max_tokens=2048` confirmed in the server log and all three values
resolving through the plugin's own loader.

### Two corrections carried out of this ticket

- **`ps` RSS under-reads MLX by 1.66×.** W17 flagged this as a caveat; here is the
  number. Two models resident read **18.64 GB** by `ps` against a real **31 GB**
  `phys_footprint` (peak 33 GB), of which `IOAccelerator (graphics)` is 27.1 GB. A
  guard threshold checked against RSS is checked against the wrong number. Use
  `footprint -p` or `vmmap -summary`.
- **A harness trap.** `urlopen(timeout=)` is a per-socket-read timeout; the
  plugin's `AbortController` is a **total** deadline. The first version scored a
  72 s request as passing a 30 s budget. Gate 0 must be judged on the wall.
- **`MemoryMonitor initialized (estimator-only, eviction disabled)` does not mean
  the server will not evict.** It is a per-engine line; `engine_pool` and
  `process_memory_enforcer` both evict, as the GLM trace shows.

### Limits kept

One coding-turn shape (13,165 tokens at `max_tokens: 2048`); a shorter turn
overlaps a larger fraction of a capture and would retain less. Gate 1's margins sit
near the noise — the control varied ±13 %, and Muse (mean 78.9 %) and Bonsai (mean
72.8 %) straddle the 75 % line by ~6 points at n=2 and n=3, so **Bonsai is a
consistent near-miss, not a decisive one**, and it did not decide this alone. The
transcript is synthetic. **`autoCaptureMaxIterations: 2` is reasoned, not
measured**: nothing here measures how often a real session needs a second
iteration.

### Also updated

`CLAUDE.md` (Memory — the settings table, the decode-bound warning, the
don't-pin-a-second-model result, and the `phys_footprint` rule; the standing "Open
question" is now answered) and `ai.env.example` (the input cap is a memory guard,
not a latency lever). `bash -n`, `python3 -m json.tool opencode.json` and the
plugin-loader check all pass.

## Question

**Which model should run opencode-mem's auto-capture summarizer, now that the default
decodes at 26 tok/s?**

`ai.sh` sets `OPENCODE_MEM_MODEL` to the session's own model on every launch, so the
default model is also the summarizer. [W18](18-default-after-capability.md) made that
model **Muse Glimmer, the slowest decoder on the roster**. The summarizer shares the model
with the coding turn through continuous batching, so every capture now steals decode from
the slowest profile — and `autoCaptureMaxIterations` is **8**, raised when contention was
believed gone.

This was fog on the map before W18; the default swap makes it live.

### Why the obvious fix is not obviously safe

`OPENCODE_MEM_MODEL` exists precisely to stop two large models sitting in memory at once.
Pinning the summarizer to Bonsai reintroduces exactly that, and the reason it was
impossible before was arithmetic that has now changed:

| | Resident |
|---|---|
| Muse Glimmer (session) | 18.59 GB |
| Ternary Bonsai (summarizer) | 8.44 GB |
| `OMLX_HOT_CACHE` | 8 GB |
| **Total** | **≈ 35 GB** |

against a memory-guard soft threshold of **40.8 GB** (85% of 48). Under the departed
~28 GB Qwen this never fit. It now appears to — but **that figure is calculated, not
measured**, it excludes both models' KV, and W12 proved the guard *under*-prices the
prefill transient it admits. A pair that fits at rest can still abort a prefill.

### Options

- **A — accept Muse as the summarizer.** No second model, no thrash risk. Costs decode on
  the slowest profile during a capture.
- **B — pin the summarizer to Bonsai.** Cheapest capable model on the roster and it
  answers the serve check. Costs 8.44 GB resident alongside the session model, and the
  guard risk above.
- **C — reduce `autoCaptureMaxIterations` under the default.** Keeps one model, cuts the
  overlap. Costs memory coverage.
- **D — disable auto-capture on the default profile.** Cheapest to implement, loses the
  feature the plugin exists for.

### What must be measured before choosing B

W14 ran with the summarizer **deliberately unreachable** — it served on port 10082 so a
live `opencode` session could not reach it — so nothing on this map has ever measured a
capture overlapping a coding turn. That measurement is this ticket's real work:

1. A coding turn's decode rate with no capture running, as the control.
2. The same turn with a capture in flight, both on Muse.
3. The same, with the summarizer pinned to Bonsai — watching for eviction, `507`s, and
   the peak resident figure against the 40.8 GB threshold.

### The floor, fixed before the run (2026-08-13)

Per the [W19](19-glm-thinking-pin.md) pattern: what result disqualifies an option, written
down before any number exists. Gate 1's threshold was chosen by the user; the other two are
preconditions, not preferences.

- **Gate 0 — the capture must complete.** A summarizer call must return its `save_memory`
  tool call inside the plugin's own per-iteration abort. An option that cannot capture is
  not a summarizer option at all, whatever it costs in memory or decode.
- **Gate 1 — contention, ≤ 25 %.** A coding turn that starts while a capture is still
  running must keep **≥ 75 % of its solo decode rate** (26 → **≥ 19.5 tok/s** on Muse), and
  must not error. Worse than that disqualifies the option.
- **Gate 2 — memory.** No eviction, no `507`, peak resident under the guard's **40.8 GB**
  soft threshold.

**Preferred lever if Gate 0 fails at full size:** shrink `OPENCODE_MEM_MAX_CONTEXT_CHARS`
until the capture fits, in preference to raising the timeout, pinning a second model, or
disabling capture. Chosen by the user before the measurement.

### Three facts read from the plugin source before measuring

These reshape the question the ticket was written with, and none of them appear in the
options above.

1. **A capture does not overlap the coding turn.** It fires on `session.idle` plus a
   **10 s debounce** (`index.js:411`), so it starts after the turn ends. The contention is
   with the **next** turn landing on a capture still in flight — which makes *capture
   duration*, not capture cost, the number that decides this ticket.
2. **Each iteration aborts at 30 s.** `autoCaptureIterationTimeout` defaults to `30000` and
   `opencode-mem.jsonc` does not set it. The provider drives an `AbortController` per
   iteration (`openai-chat-completion.js:135`), up to `autoCaptureMaxIterations` = 8.
3. **The request carries no `max_tokens`**, sets `temperature: 0.3`, sends one
   `save_memory` tool schema at `tool_choice: "auto"`, and **grows the message list every
   iteration** — so the input cap bounds only the first call.

### Note

The `memoryModel` fallback in `opencode-mem.jsonc` was repointed to Muse by W18, because
its own comment requires that value to name the default profile. It applies only to a bare
`opencode` session that `ai.sh` did not launch. Whatever this ticket decides for the
launcher, that fallback must keep naming a model oMLX can serve.

### Related

- [Decide the default profile now that capability is measured](18-default-after-capability.md)
  — made Muse the default and raised this.
- [Decide GLM's context cap against oMLX's 7x MLA over-count](12-glm-context-cap.md) —
  measured the guard under-pricing the prefill transient.
