# W14 — capability measurement: design and rubric

**Written before the run, on purpose.** [W14](../../tickets/14-capability-comparison.md)
constraint 5 says to state the rubric first, or the result is a story told after the
fact. Nothing below changed after the first request was sent. The run log records the
exact commit of this file.

## What this measures

Which of the three roster models **writes and repairs working code under an agent
loop**. It is a decision aid, not a research benchmark.

It does **not** measure long-context capability. Every prompt sits under 4,000 tokens,
well inside GLM's 32,768 cap, because [W12](../../tickets/12-glm-context-cap.md) removed
the equal footing that constraint 7 wanted. A model that fails here fails on a short
prompt; nothing here says how any of them behaves near its window.

## Serving conditions

One oMLX process, the same build and the same flags `ai.sh` uses, on **port 10082**
instead of 10081. The port is the isolation: a live `opencode` session in another
directory runs `opencode-mem`, whose summarizer targets `lmstudio-community/GLM-4.7-Flash-MLX-6bit`
on 10081. Left reachable it would load a second model mid-run and thrash the memory
guard, which is the exact failure the map documents. On 10082 it cannot reach this
server at all.

- Models load **one at a time**. The server restarts between models, so no two ever
  share the guard.
- **No `temperature` is sent.** `opencode.json` sets `"temperature": false`, so opencode
  omits the option and oMLX falls back to each model's own `generation_config.json`.
  Sending one here would measure a configuration nobody runs.
- `max_tokens: 8192` — see the amendment below.

### One amendment, made before any result was kept

The first pass used `max_tokens: 4096`, constraint 9's floor. GLM hit that cap
mid-module on T2 and scored a protocol failure. That failure was **manufactured by the
harness**: `opencode.json` gives every declared model `"output": 8192`, and
[W9](../../tickets/09-rewrite-opencode-json.md) will declare the same for this roster,
so 4096 under-provisions against production by half. Reasoning tokens count toward the
cap, and these models spend a lot of them.

The cap was raised to **8192**, which still satisfies constraint 9's "4096 or above",
and **every partial result was discarded and the suite restarted from scratch**. No
number below was produced under the 4096 cap. This paragraph exists so the change is
part of the record rather than a silent edit.

### Sampling defaults are not equal across the roster

Read from each model's `generation_config.json` before running:

| Model | File | Effect |
|---|---|---|
| GLM 4.7 Flash 6-bit | `temperature: 1.0` | samples — repeats can differ |
| Muse Glimmer 30B 4-bit | `do_sample: false` | greedy — repeats should be identical |
| Ternary Bonsai 27B 2-bit | **no file at all** | falls back to whatever oMLX defaults to |

Constraint 4 asks for repeats because "these models carry no fixed temperature". That
reasoning holds for GLM and is probably wrong for the other two. So the run **probes
determinism first** — the same prompt twice, compared byte for byte — and sets the
repeat count from the measurement instead of from the assumption. A model that is
greedy gets **1 run per task**, and the report says so. Three identical samples are not
evidence of stability; they are three copies of one sample.

## The task set

Four tasks, all drawn from work this repo actually does. Full prompts are verbatim in
[`tasks.py`](tasks.py) — that file is the record, not this summary.

| | Task | Shape | Graded by |
|---|---|---|---|
| **T1** | Find which function merges per-model settings without discarding other models | Tool chain over a simulated `scripts/` tree | Did it call tools, read the deciding file, and name the right function |
| **T2** | Write `mergeModelSettings(existing, desired)` — the both-key-spellings idempotent merge this repo really needs | Write a module | 8 assertions executed in Node |
| **T3** | Fix a cache-pruning Bash function that deletes newest-first and breaks on paths with spaces | Repair real Bash | `bash -n`, then behaviour against a temp dir with spaces in its name |
| **T4** | Write `blockingErrors(results, editedFiles)`, then extend it without regressing | Multi-turn revision | Original assertions **and** the new ones, both |

Every task is multi-turn and every task is graded by **execution**, not by reading. T1
is a tool loop. T2, T3 and T4 run the model's own output.

Why these four: T1 tests whether a model can drive tools at all, which W6 and W7 only
ever timed once and never chained. T2 is the exact idiom of `scripts/patch-omlx-mtp.mjs`,
including the both-spellings rule the map learned the hard way. T3 is a real defect
class in `ai.sh`. T4 is the `post-edit-check` loop: revise on feedback without breaking
what already worked.

### Guessing is designed to fail

T1 plants a decoy. A function named `mergeSettings` exists in a different file and
discards other models by object spread; the correct answer is `applyDesired`, in a file
the model must actually open. Answering from the name alone scores zero.

## The rubric

Stated per run, before grading:

- **pass@1** — the final requirement is satisfied on the first attempt.
- **pass@2** — satisfied after exactly **one** repair turn, where the repair turn
  carries the **real** failure output (the assertion that failed, the shell error), not
  a hint written by hand.
- **fail** — still failing after that one repair turn.
- **protocol_fail** — counted as a fail and reported **separately**: a malformed or
  unparsable tool call, no fenced code block where one was demanded, empty `content`,
  `finish_reason: length`, or generated code that touches the filesystem, the network or
  a process. This is the "unusable in an agent loop" bucket, which is a different defect
  from "wrong answer" and must not be averaged into it.

Headline numbers: **pass@1 rate** and **pass@≤2 rate** over all task-runs.

Recorded but explicitly **not** scored: wall-clock, prompt and completion tokens, and
the share of completion tokens spent on `reasoning_content`. W6 and W7 both found large
reasoning spends; this run measures the cost again but does not let it move the score.

### Safety rule on executed output

T3 makes a model write code that calls `rm`. Before any generated Bash or JavaScript
runs, it is scanned for absolute paths outside the temp directory, `sudo`, `$HOME`, `~`,
and network commands. A hit is a **protocol_fail** and the code is **not executed**.
Everything that does run, runs against a throwaway directory under the session
scratchpad.

## Result

Full tables in [`RESULTS.md`](RESULTS.md); raw per-run records with every generated
code blob in `results-*.json`. The `results-*.raw.json` files are the untouched
originals, kept because T3 was re-graded (see the correction below).

| Model | T1 tool chain | T2 merge module | T3 bash repair | T4 extend | pass@1 | pass@≤2 |
|---|---|---|---|---|---|---|
| GLM 4.7 Flash 6-bit | `1 1 1` | `1 1 P` | `P P F` | `F 1 P` | 6/12 | 6/12 |
| Ternary Bonsai 27B 2-bit | `1 1 1` | `1 P 2` | `F P F` | `2 2 1` | 5/12 | 8/12 |
| **Muse Glimmer 30B 4-bit** | `1 1 1` | `1 1 1` | `2 F 2` | `1 1 1` | **9/12** | **11/12** |

**Muse Glimmer writes the best code of the three, by a clear margin.** It is the only
model to sweep T2 and T4, the only one that repairs the Bash defect at all, and the only
one with zero runaways.

Four findings the numbers carry:

1. **Muse leads on capability while trailing on speed and memory.** The map's standing
   line — "Bonsai beats Muse on every axis" ([W7](../../tickets/07-serve-check-muse.md))
   — covered speed and memory only, and W13 kept Muse precisely because no capability
   data existed. There is data now, and it points the other way.
2. **GLM never recovers from feedback.** Its pass@1 and pass@≤2 are the same number:
   across 12 runs, not one repair turn carrying real failure output turned a failure into
   a pass. Bonsai converted 3 and Muse 2. For an agent loop built on
   `post-edit-check` throwing errors back at the model, that is the most
   decision-relevant number here — and a single-shot test would have hidden it entirely
   while ranking GLM first.
3. **GLM burns its output budget.** 4 of 12 runs ended at `finish_reason: length`,
   consuming all 8,192 tokens without producing an answer — a wasted turn, and the
   dominant reason its score sits where it does. Bonsai did it twice, Muse never.
4. **Nothing fixes the Bash defect first-shot — 0/9 on T3.** Every model corrected the
   quoting and the ordering, and every one left a real defect behind: GLM kept
   `for f in $(ls -rt ...)`, which word-splits on the spaces the contract names; Bonsai
   and Muse both reached for GNU `find -printf`, which does not exist on macOS. Only
   Muse repaired it when shown the failure. This is a shared blind spot in exactly the
   code `ai.sh` is made of, and `post-edit-check` does not lint Bash.

### Cost, recorded and not scored

| Model | Wall | Completion tokens | Reasoning chars | Runaways | Mean T1 | Tool rounds |
|---|---|---|---|---|---|---|
| GLM 4.7 Flash 6-bit | 23.0 min | 76,810 | 151,688 | 4/12 | 8.5 s | 3–5 |
| Ternary Bonsai 27B 2-bit | 32.7 min | 50,919 | 107,639 | 2/12 | 29.6 s | 2 |
| Muse Glimmer 30B 4-bit | 38.1 min | 42,097 | 155,252 | 0/12 | 74.4 s | 2–3 |

Muse is the slowest by wall clock and the **cheapest in tokens** — it reaches a better
answer with fewer of them. GLM spends the most tokens for the worst score. Reasoning is
in characters, not as a share of completion tokens: the chars-per-token ratio differs per
tokenizer, and dividing one by the other produced a nonsensical >100% for Muse.

### All three models sample, whatever their config says

The determinism probe returned `deterministic=False` for **every** model — including
Muse, whose `generation_config.json` sets `do_sample: false`, and Bonsai, which ships no
such file. **oMLX does not honour `do_sample`.** So all three got 3 repeats on equal
terms. Had the repeat count been set from the config as constraint 4 assumed, Muse would
have been run once and called stable.

### One correction, after the run

T3 was **re-graded**, and the record keeps both verdicts. The harness gave both attempts
of a task one shared working directory. Only T3 builds a directory tree, so only T3 was
affected: a failing first attempt left junk in `cache dir`, which inflated the second
attempt's `du` baseline and added stray `ls` entries, failing repair code that was
correct. Muse's T3 answers passed when re-run on bare ground.

- `run_bash_function` now wipes the directory before every attempt.
- [`regrade.py`](regrade.py) replays the **already generated** code through the fixed
  grader, so no model ran again. Two Muse runs moved `fail` → `pass@2`; GLM and Bonsai
  did not move, because their repair code genuinely fails.
- The models' inputs were never corrupted. Attempt 1 always ran on bare ground, so the
  failure output each model saw was real. Only the grading of attempt 2 was wrong.
- T1, T2 and T4 write no directory tree and are untouched.

### What these numbers are not

- **12 runs per model.** A gap of one or two is noise. 9 against 6 and 5 is the only
  comparison here worth leaning on, and even that rests on four tasks.
- **Short prompts only** — every one under 4,000 tokens, well inside GLM's 32,768 cap.
  Nothing here measures long-context capability, and Muse has the shortest native window
  of the three (131,072) with only 13 of 52 layers seeing the whole of it.
- **One task set, written by one author, run once.** It is a decision aid. It is not a
  benchmark, and it does not generalise beyond work that looks like this repo's.

## What this run may not do

[W14](../../tickets/14-capability-comparison.md) is explicit: **the result may not
silently redraw the roster.** The user chose three profiles knowing capability was
untested. A bad number gets recorded and raised as a fresh scoping decision. This asset
records; it does not decide.
