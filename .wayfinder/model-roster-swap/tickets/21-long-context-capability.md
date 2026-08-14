---
id: W21
title: Measure capability at the largest context all three profiles share
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: []
---

## Resolution (2026-08-13)

**W14's ranking does not survive at a long prompt — and neither does any other ranking.
The three models become indistinguishable, and Muse Glimmer keeps bare `ai` on the
pre-registered floor rather than on the evidence.** Run in two stages, both against a
floor fixed in writing first. Method:
[assets/w21-long-context](../assets/w21-long-context/).

### Stage 1 — the architectural worry is dead, cheaply

The ticket's stated hypothesis was specific: Muse runs 3 `sliding_attention` :
1 `full_attention` at `sliding_window: 2048`, so only **13 of 52 layers** see the whole
window, and it should fall furthest. A six-needle retrieval probe at ~22k was built to
expose exactly that shape — a failing deep set with a passing near control.

**36 of 36.** Every model, every needle, every repeat, and every answer *strict* — the
exact value, no prose, no hedge, no `UNKNOWN`, no invented value. Muse answered the needle
**21,000 tokens back** as reliably as the one 1,050 tokens back. Thirteen full-attention
layers are enough to retrieve an exact string at this distance.

The probe **saturated**, so it ranks nothing. It cost 22 minutes and it removed the reason
this ticket was urgent.

### Stage 2 — the lead dissolves; nothing replaces it

The trimmed T1/T2/T4 suite, W14's own prompts and execution graders imported unchanged,
with ~17k tokens of real repository source in the system prompt.

| Model | pass@1 4k → 17.6k | pass@≤2 4k → 17.6k | min/solved 4k → 17.6k |
|---|---|---|---|
| Muse Glimmer | 9/9 → **8/9** | 9/9 → **8/9** | 2.29 → 3.19 |
| GLM 4.7 Flash | 6/9 → **6/9** | 6/9 → **7/9** | 2.10 → **3.64** |
| Ternary Bonsai | 5/9 → **7/9** | 8/9 → **8/9** | 2.07 → **2.31** |

A pass@1 spread of **9 / 6 / 5** becomes **8 / 6 / 7**. Muse's 4-point lead over Bonsai
becomes 1 point, and on pass@≤2 they **tie at 8/9**. Every gap is inside the noise band
W14 declares for a suite this size. **The ranking did not invert — it dissolved.**

**Ternary Bonsai is the cheapest per solved task at this context (2.31) and degrades least
(1.12×). GLM degrades most (1.73×)** — the reverse of what its prefill lead predicts,
because prefill is paid once and decode is paid per token.

### The floor, applied as written

1. **Margin** — a challenger must solve **≥3 more** than Muse. Best challenger Bonsai is
   level at 8. Does not fire.
2. **Collapse** — Muse under half while a challenger leads. Muse solved 8 of 9. Does not
   fire.

**Muse Glimmer keeps bare `ai`.** Stated plainly: the *rule* holds the default here, not
the evidence. At the context this repo actually runs, the evidence is a tie.

### Two findings that correct the map, both outside what the ticket asked

- **Every decode rate in the roster table is a short-context number.** 26 / 68 / 38 tok/s
  become roughly **11 / 23 / 12.5** at 17–22k — all three lose about two-thirds. GLM keeps
  its *relative* ~2× lead, so `--glm`'s rationale is unaffected, but every absolute
  per-turn cost estimate on this map was computed at rates ~3× too high.
- **`cached_tokens` does not round to 2048 on every model.** W13 measured that on Bonsai
  and the docs generalised it. **GLM matches at 256**, re-prefilling 9–289 fresh tokens per
  turn against Muse's 1,236–1,259 — the documented rule understates GLM's cache eightfold.

### Three traps caught, recorded so nobody repeats them

- **The ticket's own cost premise was wrong**, and the map already held the correction.
  "Every repair turn re-prefills" is false for a constant head: W13 measured a repeated
  prefix restoring in 3.18 s. Confirmed here on all three models — 130.4 → 26.0 s (Muse),
  203.8 → 23.6 s (Bonsai), 92.2 → 20.6 s (GLM).
- **The ticket's `~28,000 tokens` overshoots GLM's real budget.** 28,000 + 8,192 = 36,192,
  over the declared `limit.context` of 32,768; it fits only the `max_context_window` rail,
  which guards clients that never read `opencode.json` and is not a budget any session may
  spend. The production-faithful ceiling is **24,576**.
- **Stage 1's corpus cannot be re-used for Stage 2.** The W14 tasks are drawn from this
  repo's real code and the corpus *is* this repo's real code: `scripts/patch-omlx-mtp.mjs`
  is T2's answer, `plugins/post-edit-check.js` is T4's, and T1 serves three `scripts/*`
  paths through tools in a simulated form the real files would contradict. Stage 2 uses a
  separate corpus whose builder **asserts** no answer identifier survives.

### One contaminated measurement, found and repaired

The Mac slept **75.1 minutes** mid-run (`Clamshell Sleep`, lid closed), inflating one GLM
run to 5,057 s. Verdicts are unaffected — the model generated normally at ~21 tok/s on both
sides of the gap and failed on merit — and the wall was repaired by intersecting
`pmset -g log` sleep windows with each model's server-log window: GLM 100.6 → **25.5 min**.
Muse and Bonsai overlapped no sleep. **Arm `caffeinate` before a long measurement on this
box**, and note it cannot override clamshell sleep.

### Also decided

- **The context caps do not converge.** Nothing at 17.6k distinguishes the models, so there
  is no evidence for moving GLM off 32,768 (fixed permanently by W17 on time, not memory)
  or the other two off 65,536 (W13).
- **A result here can move the default in principle** — the floor was live, and Bonsai came
  within 1 solved task of a tie that a 3-margin would still not have converted. What a
  9-run suite cannot do is separate models that sit within noise of each other.

## Question

**Does W14's capability ranking survive at a long prompt?** W14 measured **Muse Glimmer
9/12, GLM 6/12, Bonsai 5/12** on prompts every one of which was under **4,000 tokens**,
and W18 picked the default from that result. Nothing on this map measures capability near
a full window.

This was fog until now, held back by one thing: GLM's 32,768 cap made a fair shared
prompt look temporary, so a measurement would have been obsolete the moment the cap rose.
[W17](17-glm-prefill-headroom.md) settles that — **the cap is permanent**. It is a time
limit, not a memory limit, so no lever moves it and it does not move if a future oMLX
fixes its guard. The shared window is fixed at 32,768 for good, and a measurement taken
there stays valid.

### Why it matters more than a routine follow-up

**The evidence behind the default is furthest from where the default is weakest.**

- W18's deciding metric — minutes per solved task — was computed at **~1.5k-token**
  prompts.
- Muse Glimmer has the **shortest native window** on the roster (131,072) and the
  weakest long-range structure: `layer_types` runs 3 sliding : 1 full, so only **13 of
  52 layers** ever see the whole window. The other 39 see a 2,048-token slice.
- So the model chosen on short-prompt evidence is the one whose architecture predicts the
  steepest fall on long prompts — and this repo's own agent loop runs 12–25k contexts
  routinely.

If the ranking inverts at 28k, the default is wrong for the work it actually does.

### Shape

- **Prompt size**: ~28,000 tokens, leaving room under GLM's 32,768 for `output: 8192`.
  One shared prompt for all three, so the comparison stays single-variable — which W12
  §7 notes W14's could not be.
- **Harness**: re-use [assets/w14-capability](../assets/w14-capability/). Grade by
  **executing** each model's output, as W14 did. Keep the pass@1 / pass@2 split, the
  protocol-failure count, and the runaway count.
- **Budget**: measure at `output: 8192`, per constraint 9.
- **Fix the floor before the run**, as W19 established: state what result would change
  the default, in writing, before any number exists.

### The cost is the real obstacle, and it must be priced first

W17's fitted curves put a single cold 28,000-token door charge at roughly **95 s for
GLM** and roughly **180 s for Muse**. W14 ran 4 tasks x 3 repeats x 3 models, multi-turn.
At that size the suite is hours, not minutes, and every repair turn re-prefills.

So the first work in this ticket is **not** the measurement. It is deciding what the
smallest suite is that could still move the default — fewer tasks, fewer repeats, or a
single task chosen because it discriminates. A suite that cannot change a decision is not
worth its wall-clock.

### Decide as well

- Whether a result here can move the default at all, or only annotate it. W18 chose on
  minutes per solved task; that metric needs re-deriving at this size, because the door
  charge dominates differently.
- Whether `--glm`'s 32,768 and the other two's 65,536 should converge, if the ranking at
  28k differs sharply from the ranking at 4k.

### Related

- [Measure coding capability across the three profiles](14-capability-comparison.md) —
  the 4k result and the harness.
- [Decide the default profile now that capability is measured](18-default-after-capability.md)
  — chose Muse on that result.
- [Buy prefill headroom for GLM](17-glm-prefill-headroom.md) — fixed the shared window
  permanently, and supplies the prefill cost model.
- [Measure GLM with thinking pinned off](19-glm-thinking-pin.md) — the fix-the-floor-first
  pattern.
