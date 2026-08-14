---
id: W19
title: Measure GLM with thinking pinned off
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: [W18]
---

## Question

**Does pinning thinking off cure GLM's runaways, and does GLM then win the default
back?**

[W18](18-default-after-capability.md) moved the default to Muse Glimmer and left GLM as
the fast opt-in profile. It also registered the bar GLM must clear to take the default
again, **before** any measurement runs — so this ticket executes a pre-registered test
rather than telling a story afterwards.

### Why the defect looks settings-shaped

[W14](14-capability-comparison.md) recorded four of GLM's six failures as runaways
(`finish_reason: length`), not wrong answers. GLM spends **151,688 reasoning characters to
produce 76,810 completion tokens** — the worst ratio on the roster. It reasons until the
output budget is gone, then returns nothing.

The lever exists and has never been tried. GLM's chat template honours `enable_thinking`:

```jinja
<|assistant|>{{- '</think>' if (enable_thinking is defined and not enable_thinking) else '<think>' -}}
```

`ms.enable_thinking` takes precedence over `chat_template_kwargs` in `omlx/server.py`, and
`scripts/patch-omlx-mtp.mjs` still carries the merge machinery with an empty `DESIRED`
map — W8 kept it wired for exactly this. The entry must be written under **both** the
two-level id and the directory leaf `GLM-4.7-Flash-MLX-6bit`; the script already does
both, and a leaf-less entry is silently never consulted.

**The upside is large enough to be worth the session.** If the pin removes all four
runaways, GLM moves from 6/12 toward 10/12 — a bigger swing than the 9-against-6 gap the
default decision rests on.

### The bar — fixed by W18, not to be renegotiated here

1. **Capability floor: GLM must solve at least 9 of 12** (pass@≤2). Muse's 11 less the
   2-run noise band W14 declares.
2. **Then minutes per solved task decides.** GLM needs roughly **≤31 min for 9 solved**
   to beat Muse's 3.46. Divide the run's own wall-clock by its solved count, the same way
   W18 computed the table.

**Recovery is reported, not gated.** GLM recovered 0 times in 12 runs. The solved count
already counts a failed repair as a failure, so gating on recovery double-counts it.
Record the number: a persistent 0/12 stays a standing warning for the `post-edit-check`
loop, which throws real errors back at the model.

### Method

Re-run W14's suite against **GLM only** — `assets/w14-capability/run-all.sh` with its
fixed prompts, 4 tasks × 3 repeats, `max_tokens: 8192`, graded by executing the model's
own output. Do not re-run Muse or Bonsai: they have no pin to change, ~95 min against
~25 min buys only a second sample of noise, and the floor above already absorbs the
cross-session drift. Note that oMLX **ignores `do_sample`** (W14), so every run samples
and a gap of one or two is noise.

Report against the stored `results-glm.json` as the control, so the pin is the only
variable that moved.

### Decide as well

- **Does the pin stay on the `--glm` profile even if GLM does not retake the default?**
  These are separate questions. Fewer wasted turns may be worth having on the opt-in fast
  profile regardless of what serves bare `ai`.
- **What if the pin lowers pass@1?** GLM's reasoning may be what makes it correct. Then
  revert the `DESIRED` entry and record the result — a measured "no" is worth the session.

### Related

- [Decide the default profile now that capability is measured](18-default-after-capability.md)
  — set this bar and moved the default.
- [Measure coding capability across the three profiles](14-capability-comparison.md) — the
  suite, the rubric and the control numbers.

## Resolution

**The pin cures the defect exactly as predicted and loses anyway. It is off, GLM keeps
`--glm`, and Muse Glimmer stays the default.**

Method, limits and every generated blob: [assets/w19-thinking-pin](../assets/w19-thinking-pin/).

### 1. The lever engaged — proved before the suite, not assumed

A null result is worthless if the setting never took hold, so the pin was probed either
side of a restart with the same two prompts. Reasoning 2,607 chars → **0**; the real T2
prompt went from `finish_reason: length` at 8,192 tokens and 132.25 s to `stop` at 311
tokens and **4.76 s**.

That pin-off probe also reproduced W14's runaway **on the first real task**, and showed
how it presents: `reasoning_content` **empty**, all 32,997 chars of reasoning sitting in
`content`. oMLX splits the two only once it sees the closing tag, so the runs that
reasoned hardest report zero reasoning. This explains a confusing column in W14's raw
data rather than changing its verdicts.

### 2. The result

| Run | T1 | T2 | T3 | T4 | pass@1 | pass@≤2 |
|---|---|---|---|---|---|---|
| control, thinking **on** | `1 1 1` | `1 1 P` | `P P F` | `F 1 P` | 6/12 | **6/12** |
| pinned, thinking **off** | `1 1 1` | `F F F` | `F F F` | `F 2 F` | 3/12 | **4/12** |

Runaways **4/12 → 0/12**. Reasoning 151,688 chars → **0**. Wall **23.0 → 1.9 min** on a
twelfth of the tokens. And solved **6 → 4**.

### 3. Against the bar W18 fixed in advance

- **Floor — ≥ 9/12 solved: got 4/12. FAIL.**
- Speed — ≤ 3.46 min/solved: got **0.47**. Passes, and is irrelevant; the floor is first.

**GLM does not retake the default.**

**This run is the argument for having a floor at all.** At 0.47 min/solved the pinned GLM
scores **7× better than Muse on W18's own deciding metric** while solving a third as many
tasks — because a model that fails fast is cheap per outcome. W18 fixed the floor before
any measurement ran, and it is the only thing standing between this map and a default
chosen by that number.

### 4. Why it costs capability

The reasoning is load-bearing, and T2 — the both-key-spellings merge, the exact idiom of
`patch-omlx-mtp.mjs`, the file the pin is written into — shows it cleanly. The control's
two T2 passes cost **9,431** and **26,413** reasoning chars; remove the reasoning and both
go. The pinned failures are substantive, not truncated: `version` not defaulting to 1, the
`changed` flag never going true, both spellings written but empty. Pinned GLM also
imported **packages that do not exist** (`lodash-es`, `deepmerge`) where the control did so
zero times in 12 runs, and emitted Bash that fails `bash -n`, a failure class the control
never produced.

**The cure converts wasted turns into wrong answers, not right ones.** T3 is the exact
demonstration: `P P F` → `F F F`. Three failures either way.

### 5. Decided as well

- **Does the pin stay on `--glm` regardless of the default?** **No.** It buys nothing on
  the count that matters — T3 proves the point at zero solved either way — and costs a
  point estimate. There is no version of "fast" worth having when the fast answers are
  wrong and GLM recovers 1 time in 12. `DESIRED` is reverted and reasoning was confirmed
  restored on a live server.
- **What if the pin lowers pass@1?** It did, and this ticket takes the branch it
  pre-registered: revert and record. A measured "no" closes a lever that would otherwise
  stay open forever as an untried idea.

### 6. Honest limit on the capability claim

**6 → 4 sits inside the noise band this suite declares** (W14: over 12 runs a gap of one
or two is noise). So the defensible claim is **no measured gain plus a point-estimate
loss**, not proof of harm. The default decision does not rest on it: 4 against a floor of
9 is a gap of five. The per-task detail is the stronger evidence — T2's 2 → 0 with a
visible mechanism.

### 7. A trap the revert exposed

**`patch-omlx-mtp.mjs` never deletes a key**, by design, so it can preserve admin-panel
settings. That means **removing an entry from `DESIRED` does not remove the live
setting** — verified on a throwaway file, where a stale `enable_thinking: false` survived
a re-run untouched. Had the revert been "delete the line and re-run", GLM would have kept
running pinned while the repo said otherwise, and the next measurement would have been
silently poisoned. The key was deleted from `~/.omlx/model_settings.json` by hand; the
file now diffs clean against its pre-session backup, and the script carries a comment
warning the next person.

### 8. State left behind

`scripts/patch-omlx-mtp.mjs` — `DESIRED` unchanged in effect, comment rewritten to record
that the pin was **tried and measured**, so nobody re-tries it blind. Unit-tested on a
throwaway path (fresh create, idempotent re-run, foreign model and key preserved, corrupt
file recovered, admin-panel toggle re-asserted). `~/.omlx/model_settings.json` byte-identical
to its pre-session state. No server left running.
