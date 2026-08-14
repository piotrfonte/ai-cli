---
id: W14
title: Measure coding capability across the three profiles
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: [W13]
---

## Question

**Which of the three models writes the best code?** Nothing on this map has asked.

[W13](13-roster-after-prefill.md) §3 is the reason this exists. W5, W6 and W7 each ran
a *serve check* — `finish_reason: stop`, non-empty `content`, reasoning split out, a
tool call that parses. That gate proves a model **works**. It says nothing about
capability, and the map had let "dominated on every measured axis" stand in for a
capability claim it had no data for. The roster is currently chosen on **speed and
memory alone**.

### What exists today

| | Evidence of capability |
|---|---|
| GLM 4.7 Flash 6-bit | One linked-list reversal, correct. Nothing else. |
| Bonsai 27B 2-bit | One linked-list reversal, correct. Vendor card claims 95% of FP16 retained, 80.49 average over 15 thinking-mode benchmarks vs 72.73 for IQ2_XXS — **unverified, and against its own FP16, not against the other two.** |
| Muse Glimmer 30B 4-bit | One 341-char function, correct. Nothing else. |

No head-to-head. Different lineage, no shared benchmark.

### The comparison is no longer single-variable — W12

Constraint 7 wanted one flat context across all three so a capability result would be
model-vs-model. That is gone: [W12](12-glm-context-cap.md) measured GLM's ceiling and
it declares **32,768**, against 65,536 for Bonsai and Muse. The cause is structural
(the prefill activation transient against Apple's Metal cap), not a setting to undo, so
this ticket cannot restore the equal footing by choosing a number.

Two consequences for the method here:

- **Keep every task's prompt well inside 32,768** so context is not silently a second
  variable. A task that fits GLM's window on all three models is a fair test; one that
  only Bonsai and Muse can hold is not.
- **Do not read a GLM loss on a long-context task as a capability result.** It may be
  the cap. Say which was tested.

**Bonsai carries the sharpest open risk**: it is a **2-bit** ternary fine-tune of
`Qwen/Qwen3.6-27B`, by far the most aggressive quantization on the roster. If the
vendor's 95% claim does not hold on real work, its 8.44 GB stops being a bargain.

### What this ticket must produce

A **small fixed task set**, run across all three profiles, with the results recorded so
the roster rests on evidence rather than a card. Not a research benchmark — a decision
aid.

Design constraints:

1. **Real coding tasks**, drawn from work this box actually does — this repo's own Bash
   and ESM patch scripts are fair game, as are the kinds of edits `post-edit-check`
   guards. A linked-list reversal is what failed to be informative last time.
2. **Multi-turn and tool-using**, not single-shot. The roster is for agentic coding, so
   a model that answers well but drives tools badly is not usable. W6 and W7 both timed
   one tool call; neither tested a chain.
3. **Fixed prompts, recorded verbatim**, so a re-run after any quant or drafter change
   is comparable.
4. **Repeat each task**, because these models carry no fixed temperature — they fall
   back to their own `generation_config.json`. A single sample is noise.
5. **State the rubric before running.** Decide what counts as a pass first, or the
   result is a story told after the fact.
6. **Budget the time.** A full window is 7 m 24 s cold on Bonsai. Keep tasks near the
   ~12k door charge and re-use prefixes where the design allows — see the
   [W13 asset](../assets/w13-prefix-extension/) for how the prefix cache behaves.

### What it must not do

**Do not let the result silently redraw the roster.** The user chose three profiles
knowing capability was untested. If a model measures badly, that is a fresh scoping
decision, not this ticket's to take — record the number and raise it.

### Related

- [Decide the roster now that Bonsai prefills at ~200 tok/s](13-roster-after-prefill.md)
  — §3 is the argument this ticket answers.
- [Rewrite CLAUDE.md and ai.env.example for the new roster](11-rewrite-claude-md.md) —
  must state the gap plainly if this ticket has not closed by then.

## Resolution

**Muse Glimmer writes the best code of the three, and the roster's speed ranking is the
reverse of its capability ranking.** Method, full tables and every generated code blob:
[assets/w14-capability](../assets/w14-capability/).

| Model | T1 tool chain | T2 merge module | T3 bash repair | T4 extend | pass@1 | pass@≤2 |
|---|---|---|---|---|---|---|
| GLM 4.7 Flash 6-bit | `1 1 1` | `1 1 P` | `P P F` | `F 1 P` | 6/12 | 6/12 |
| Ternary Bonsai 27B 2-bit | `1 1 1` | `1 P 2` | `F P F` | `2 2 1` | 5/12 | 8/12 |
| **Muse Glimmer 30B 4-bit** | `1 1 1` | `1 1 1` | `2 F 2` | `1 1 1` | **9/12** | **11/12** |

`1` = pass@1 · `2` = pass@2 (one repair turn carrying the real failure output) · `F` =
fail · `P` = protocol failure. Four tasks × 3 repeats × 3 models, every task multi-turn
and graded by **executing** the model's own output — 8 assertions in Node for T2, a
behaviour test against a directory with spaces in its name for T3, both requirement sets
at once for T4, and a tool loop over a simulated `scripts/` tree with a planted decoy for
T1.

### What the numbers say

1. **The capability order inverts the speed order.** Muse is slowest to decode (26 tok/s)
   and heaviest to prefill, and it wins on capability by a clear margin. The map's
   standing line — "Bonsai beats Muse on every axis" ([W7](07-serve-check-muse.md)) —
   was about speed and memory, and [W13](13-roster-after-prefill.md) kept Muse precisely
   because no capability data existed. There is data now, and it favours Muse.
2. **GLM never recovers from feedback — 0 recoveries in 12 runs.** Its pass@1 and pass@≤2
   are the same number. Bonsai converted 3 failures into passes, Muse 2. This repo's
   agent loop is built on `post-edit-check` throwing errors back at the model, so a model
   that cannot act on a real error message is weak exactly where it is needed. A
   single-shot test would have ranked GLM first and hidden this.
3. **GLM burns its output budget: 4 of 12 runs hit `finish_reason: length`**, spending all
   8,192 tokens without producing an answer. That is a wasted turn in production. Bonsai
   did it twice; Muse never did.
4. **Nothing fixes the Bash defect first-shot — 0/9 on T3.** All three corrected the
   quoting and the ordering and all three left a real defect: GLM kept
   `for f in $(ls -rt ...)`, which word-splits on the spaces the contract names; Bonsai
   and Muse reached for GNU `find -printf`, which does not exist on macOS. Only Muse
   repaired it when shown the failure. That is a shared blind spot in exactly the kind of
   code `ai.sh` is made of, and `post-edit-check` does not lint Bash at all.
5. **Muse is the cheapest in tokens** (42k completion tokens against GLM's 77k) while
   scoring highest. It costs wall-clock, not tokens.
6. **Bonsai's 2-bit quant shows no collapse.** This ticket named it the sharpest open
   risk. It lands between the other two, repairs well, and its failures are ordinary
   mistakes, not degeneracy. The vendor's 95% claim is still unverified, but nothing here
   contradicts it.

### Two method findings worth keeping

- **oMLX does not honour `do_sample`.** The determinism probe returned
  `deterministic=False` for every model, including Muse, whose `generation_config.json`
  sets `do_sample: false`, and Bonsai, which ships no such file. Setting the repeat count
  from the config — as this ticket's constraint 4 implied — would have run Muse once and
  called it stable.
- **`max_tokens: 4096` is below production.** A first pass at constraint 9's floor made
  GLM hit the cap mid-module. `opencode.json` gives every declared model `output: 8192`,
  so 4096 under-provisions by half. The cap was raised to 8192, **every partial result was
  discarded, and the suite was restarted from scratch.** No number above was produced
  under the 4096 cap.

### One correction, disclosed

T3 was re-graded after the run. The harness gave both attempts of a task one shared
working directory; only T3 builds a directory tree, so a failing first attempt polluted
the state the repair was tested in. `run_bash_function` now wipes the directory, and
`regrade.py` replayed the already-generated code through the fixed grader — no model ran
again. Two Muse runs moved `fail` → `pass@2`; GLM and Bonsai did not move. The models'
inputs were never wrong: attempt 1 always ran on bare ground, so the failure output each
model saw was real. Untouched originals are kept as `results-*.raw.json`.

### Scope — this ticket records, it does not redraw

Per this ticket's own "What it must not do", the result **does not change the roster**.
Two decisions it raises, both fresh:

- **The default profile.** GLM is the default because it prefills ~3× faster than
  anything else, chosen when capability was unmeasured. It now measures worst of the
  three, never recovers from feedback, and wastes a third of its turns. Whether that
  trade still holds is
  [Decide the default profile now that capability is measured](18-default-after-capability.md).
- **Bash is unguarded.** T3's 0/9 is a blind spot in the language `ai.sh` is written in,
  and `post-edit-check` lints only JS/TS. Carried as fog on the map.

### Limits

12 runs per model, four tasks, one author, one run. A gap of one or two is noise; 9
against 6 and 5 is the only comparison worth leaning on. Every prompt is under 4,000
tokens, well inside GLM's 32,768 cap, so **nothing here measures long-context
capability** — which is where Muse is structurally weakest (131,072 native window, only
13 of 52 layers seeing all of it). This is a decision aid, not a benchmark.
