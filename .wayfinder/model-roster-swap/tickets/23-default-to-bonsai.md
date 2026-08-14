---
id: W23
title: Move the default profile to Ternary Bonsai
map: model-roster-swap
labels: [wayfinder:decision]
status: closed
assignee: claude
blocked_by: [W18, W21]
---

## Question

**Should bare `ai` still serve Muse Glimmer?**

[W18](18-default-after-capability.md) made Muse the default on a four-task suite at prompts
under 4,000 tokens, where it led 9/12 to GLM's 6/12 and Bonsai's 5/12. [W21](21-long-context-capability.md)
then re-ran the three separating tasks at **~17.6k**, which is the length an agent turn in
this repo actually holds, and the lead disappeared:

| | pass@1 4k → 17.6k | pass@≤2 4k → 17.6k | min/solved 4k → 17.6k | Resident |
|---|---|---|---|---|
| Muse Glimmer | 9/9 → **8/9** | 9/9 → **8/9** | 2.29 → 3.19 | 18.59 GB |
| GLM 4.7 Flash | 6/9 → 6/9 | 6/9 → 7/9 | 2.10 → 3.64 | 22.89 GB |
| Ternary Bonsai | 5/9 → **7/9** | 8/9 → **8/9** | 2.07 → **2.31** | **8.44 GB** |

W21 left the default where it was, because its floor was fixed in writing before the run —
a challenger had to lead by three tasks, and Bonsai only drew level. That is a rule about
**not moving on noise**. It is not evidence that Muse leads.

## Decision

**Bare `ai` serves Ternary Bonsai 27B 2-bit from 2026-08-14. Muse Glimmer keeps the model
flag it already had, `--muse`.** Decided by the user; recorded here rather than derived here.

What the decision leans on, all of it from W21:

- **Capability no longer separates the three at this length.** 7 / 8 / 6 on pass@1, a tie at
  8/9 on pass@≤2 between Bonsai and Muse, every gap inside the noise band.
- **Bonsai is the cheapest per solved task there** — 2.31 min against 3.19 and 3.64 — and it
  **degrades least** from short to long, 1.12× against 1.39× and 1.73×.
- **It is less than half the resident footprint**, 8.44 GB against 18.59. That margin is what
  the 8 GB hot tier, a summarizer capture and the OS draw on, and it is the reason a second
  resident model is less likely to thrash the memory guard.
- **It takes feedback best of the three** (W14: 5/12 → 8/12 with one repair turn, three real
  recoveries), which is what `post-edit-check` demands of a model in this repo's agent loop.

## What it costs, plainly

- **Muse's short-prompt lead is real and is given up**: 9/12 against 5/12 pass@1, 3.46 against
  4.09 min per solved task. It is the largest measured capability gap on this roster.
- **W18's pre-registered floor is not met.** A +3 lead was required of a challenger; Bonsai
  drew level. The default moved on footprint and cost per solved task at agentic length, not
  on a capability win. Anyone re-opening this should re-open it with a measurement.
- **The default now fills the KV cache.** Bonsai's KV is fp16 at ~64 KB/token against Muse's
  ~13, so the 8 GB hot tier fills and spills to SSD in ordinary use. `_prune_cache` and the
  25 GB disk budget matter more than they did.
- **Bonsai has the tightest patience boundary of the three**: ~21,000 tokens in 120 s
  (interpolated between its measured 66.20 s at 12.8k and 147.52 s at 25k), against Muse's
  ~22,800 and GLM's ~32,311.
- **The summarizer timings were measured on Muse and were not re-measured.**
  `opencode-mem.jsonc` keeps its 180 s iteration timeout and 2 iterations, which a `--muse`
  session still needs. No capture has been timed on Bonsai.

## What changed in the tree

- `ai.sh` — the `case "$profile"` arm: `""` and `bonsai` now reach `_model_bonsai`, `muse`
  reaches `_model_muse`. Help text, the retired-flag roster and every profile comment follow.
  **No fail-safe changed**, which is the point of two earlier design choices: the GLM context
  guard keys on the profile **name** rather than a `"default"` sentinel (W18), and the Muse
  tool-call warning keys on the **model id** rather than the flag (W22). Both stayed correct
  across the move without an edit.
- `opencode-mem.jsonc` — `memoryModel`, the fallback a bare `opencode` uses, moves with the
  default. The three W20 settings do not move.
- `CLAUDE.md`, `CONTEXT.md`, `ai.env.example` — the roster table is reordered, the section
  arguing the old default is rewritten as **Why the default is Bonsai**, and every
  Muse-measured figure that used to read as "the default" is now labelled `--muse`.

## Related

- [Decide the default profile now that capability is measured](18-default-after-capability.md)
  — the rule this decision does not satisfy, and why the rule exists.
- [Measure capability at the largest context all three profiles share](21-long-context-capability.md)
  — the measurement it leans on, and its declared limits: 9 runs over 3 tasks cannot resolve
  a one-task gap.
- [Decide the summarizer model now the default decodes at 26 tok/s](20-summarizer-model.md) —
  the settings that stayed put.
