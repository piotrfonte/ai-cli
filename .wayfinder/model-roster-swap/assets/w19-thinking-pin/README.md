# W19 — GLM with thinking pinned off: method and result

[W19](../../tickets/19-glm-thinking-pin.md) executes a test **W18 registered before it
ran**. The bar was fixed in advance and is applied here unchanged, so this is a measured
answer rather than a story told afterwards.

## What moved, and what did not

One variable: `enable_thinking: false` for GLM in `~/.omlx/model_settings.json`, written
by `scripts/patch-omlx-mtp.mjs` under **both** key spellings. Everything else is W14's:
the same `run.py`, the same `tasks.py` prompts, `max_tokens: 8192`, 4 tasks × 3 repeats,
port 10082, graded by **executing** the model's own output. The control is W14's stored
`results-glm.json`, not a re-run.

Same box, same build as W14 — `omlx 0.5.8.dev3` at `350dc08b` — and `tasks.py` already
carried W14's T3 wipe fix, so both runs are graded by the same grader.

## The lever engages — proved before the suite ran, not assumed

A null result is worthless if the setting never took hold, so the pin was probed either
side of a server restart with the same two prompts ([`probe.py`](probe.py)).

| | pin off | pin on |
|---|---|---|
| short probe, reasoning chars | 2,607 | **0** |
| short probe, completion tokens | 549 | 36 |
| T2 real prompt, `finish_reason` | **length** | **stop** |
| T2 real prompt, completion tokens | 8,192 | 311 |
| T2 real prompt, wall | 132.25 s | **4.76 s** |

The pin-off probe also **reproduced W14's runaway on the very first real task**, and
showed how it presents: 8,192 tokens, `finish_reason: length`, and **`reasoning_content`
empty** with all 32,997 chars of reasoning in `content`. oMLX only splits the two once it
sees the closing tag, so a run that never reaches it reports zero reasoning. That is why
W14's per-run reasoning figure reads 0 on exactly the runs that reasoned the most.

Why it works: GLM's template is
`<|assistant|>{{- '</think>' if (enable_thinking is defined and not enable_thinking) else '<think>' -}}`,
and `ModelSettings.enable_thinking` is a dedicated toggle that outranks
`chat_template_kwargs` (`omlx/model_settings.py`, `merge_chat_template_request_kwargs`).
The harness sends neither `chat_template_kwargs` nor `thinking`, so nothing competes.

## Result

| Run | T1 tool chain | T2 merge | T3 bash | T4 extend | pass@1 | pass@≤2 |
|---|---|---|---|---|---|---|
| GLM control, thinking **on** | `1 1 1` | `1 1 P` | `P P F` | `F 1 P` | **6/12** | **6/12** |
| GLM pinned, thinking **off** | `1 1 1` | `F F F` | `F F F` | `F 2 F` | **3/12** | **4/12** |

| Run | Wall | Completion tokens | Reasoning chars | Runaways | Recoveries | min/solved |
|---|---|---|---|---|---|---|
| thinking on | 23.0 min | 76,810 | 151,688 | **4/12** | 0/12 | 3.83 |
| thinking off | **1.9 min** | 6,897 | **0** | **0/12** | 1/12 | **0.47** |

**The pin does exactly what it was aimed at and still loses.** Every runaway is gone and
the suite runs 12× faster on a twelfth of the tokens. But solved falls 6 → 4, and the bar
needed **9**.

## Against the pre-registered bar

- **Floor — ≥ 9/12 solved: got 4/12. FAIL.**
- Speed — ≤ 3.46 min/solved: got 0.47. Pass, and irrelevant: the floor is checked first.

**GLM does not take the default back. Muse Glimmer stays.**

### The floor is not decoration — this run is the proof

At 0.47 min/solved the pinned GLM is **7× "better" than Muse on W18's deciding metric**
while solving a third as many tasks. A model that fails fast scores brilliantly on
minutes-per-solved. W18 put the capability floor first and fixed it before any
measurement ran; had the metric been applied alone, it would have crowned this run.

## Why it costs capability

The reasoning is load-bearing, and T2 shows it cleanly. T2 is the both-key-spellings
idempotent merge — the exact idiom of `scripts/patch-omlx-mtp.mjs`, the file this pin is
written into.

- Control T2 passes cost **9,431** and **26,413** reasoning chars. Remove the reasoning,
  lose the passes: 2 solved → **0**.
- The pinned failures are substantive, not truncated: `version` not defaulting to 1, the
  `changed` flag never going true, both key spellings written but left empty.
- **Packages that do not exist.** Pinned GLM imported `lodash-es` (suite) and `deepmerge`
  (probe). The control did this **zero** times across all 12 runs.
- **A new failure class**: T3[1] produced Bash that fails `bash -n`. The control never
  emitted unparsable Bash.

**The cure converts wasted turns into wrong answers, not right ones.** T3 is the exact
demonstration: `P P F` → `F F F`. Three failures either way; only the flavour changed.

## Honest limits

- **6 → 4 sits inside the noise band this suite declares.** W14's README says a gap of one
  or two is noise over 12 runs. So the correct claim is that the pin showed **no measured
  gain** and a point-estimate loss — not that it certainly harms. The *default* decision
  does not depend on this: 4 against a floor of 9 is a gap of five.
- **T4 is unchanged in score** (1 solved → 1 solved), though the pinned run produced GLM's
  **first recovery on this map** (1/12 against the control's 0/12). One is noise; the
  standing "GLM never recovers" warning is softened, not lifted.
- **Short prompts only**, all under 4,000 tokens, inherited from W14. Nothing here speaks
  to long context.
- **Wall-clock is not perfectly matched.** The control restarted the server per model and
  paid a cold model load; this run reused a server already warm from the probe, and the
  SSD KV tier held blocks for these fixed prompts. Worth at most tens of seconds against a
  23.0 min control, and it cannot move a 6-vs-4 capability count.

## The revert, and a trap it exposed

The pin is **off**. `DESIRED` is back to `{ max_context_window: 36864 }`, and reasoning
was confirmed restored on a live server after restart (1,366 and 7,827 chars —
[`probe-reverted.json`](probe-reverted.json)).

**`patch-omlx-mtp.mjs` never deletes a key.** That is deliberate and documented — it must
preserve anything set through the oMLX admin panel — but it means **removing an entry from
`DESIRED` does not remove the live setting**. Verified on a throwaway file: a stale
`enable_thinking: false` survives a re-run untouched. The key had to be deleted from
`~/.omlx/model_settings.json` by hand, and the file now diffs clean against its
pre-session backup. A comment in the script records this for the next person.

## Files

- [`compare.py`](compare.py) — grader; applies the bar unchanged. `python3 compare.py
  ../w14-capability/results-glm.json results-glm-nothink.json`
- [`comparison.md`](comparison.md) — its full output, including per-run failure detail
- [`results-glm-nothink.json`](results-glm-nothink.json) — every run, with generated code
- [`probe.py`](probe.py), `probe-pinoff.json`, `probe-pinon.json`, `probe-reverted.json`
- [`glm-nothink-run.log`](glm-nothink-run.log) — the run log
- Harness and control live in [`../w14-capability/`](../w14-capability/)
