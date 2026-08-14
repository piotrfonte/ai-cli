# W21 Stage 1 — long-context retrieval probe: design and decision rule

**Written before the first request was sent.** [W19](../../tickets/19-glm-thinking-pin.md)
established the pattern: state what result changes the decision, in writing, before any
number exists. Nothing below changed after the run started. The run log records the commit
of this file.

## Why a probe comes before the suite

[W21](../../tickets/21-long-context-capability.md) asks whether W14's capability ranking —
**Muse Glimmer 9/12, GLM 6/12, Bonsai 5/12** — survives at a long prompt. W14 measured only
short prompts, every one under 4,000 tokens, and W18 chose the default from that result.

The ticket assumed cost forces a small suite. It does not, and the map already held the
correction: [W13](../w13-prefix-extension/README.md) measured a repeated 12.8k prefix
restoring in **3.18 s** against 58.63 s cold. A corpus held **constant at the head of every
prompt** is prefilled once per model, not once per turn, so the full four-task suite at this
size costs about 110 minutes against W14's 94 — roughly 20 % more, not "hours, not minutes".

So the suite is affordable. The probe still comes first, because it tests the ticket's
**stated hypothesis** directly and cheaply:

> Muse Glimmer has the shortest native window on the roster (131,072) and the weakest
> long-range structure: `layer_types` runs 3 `sliding_attention` : 1 `full_attention` at
> `sliding_window: 2048`, so only **13 of 52 layers** ever see the whole window.

That is a claim about **retrieval across distance**. A coding suite measures it only
indirectly, through four tasks and a grader. This probe measures it in about 30 minutes.

## What this measures

Whether each model can return an **exact fact** from a load-bearing corpus, as a function
of how far back in the window that fact sits.

It does **not** measure code quality at length. A model can quote a constant correctly and
still write worse code over a long context. This sentence exists so that a clean probe
cannot be read afterwards as a clean bill of health.

## The corpus is real source, and nothing in it is planted

`corpus.txt` is built by [`build_corpus.py`](build_corpus.py) from four files of this
repository, concatenated in a fixed order with one header line each:

| Depth | File |
|---|---|
| 0.0 % | `opencode.json` |
| 5.0 % | `scripts/patch-omlx-mtp.mjs` |
| 17.7 % | `ai.sh` |
| 84.1 % | `plugins/post-edit-check.js` |

Nothing is generated, paraphrased or planted. An agentic session in this repository holds
exactly this kind of text, so a fact retrieved from it is a fact the model read, not one a
harness invented for it. The file order is chosen for **depth spread**, not for realism of
ordering: two small files at the head and one at the tail bracket the large one, so needles
can sit across the whole window.

### The size is ~22k tokens, not the ticket's 28,000 — and the ticket's number is wrong

W21 asks for "~28,000 tokens, leaving room under GLM's 32,768 for `output: 8192`". That
arithmetic does not close: 28,000 + 8,192 = **36,192**, which is over GLM's declared
`limit.context` of 32,768. It fits only GLM's `max_context_window` **rail** of 36,864 — and
the rail is a guard against clients that never read `opencode.json`, not a budget any
opencode session may spend. A real session on `--glm` compacts before it reaches 28,000
tokens with 8,192 reserved.

The production-faithful ceiling is therefore **32,768 − 8,192 = 24,576 prompt tokens**. The
corpus is sized just under it, on the hungriest tokenizer:

| Tokenizer | Corpus tokens |
|---|---|
| Muse Glimmer | 21,594 |
| GLM 4.7 Flash | 21,925 |
| Ternary Bonsai | **23,217** |

76,782 characters. Bonsai counts **7.5 % more tokens for the same bytes** than Muse, which
is why the corpus is sized against Bonsai and not against an average. With the question and
the chat template added, Bonsai stays near 23,4xx, leaving the full 8,192 output inside
32,768.

This is 5.4–5.8× the largest prompt W14 ever sent, and it is the largest corpus that keeps
**all three** models inside the budget a real `--glm` session actually gets.

## The needles

Six facts, each occurring **exactly once** in the corpus, verified by string count. Each is
load-bearing repository detail that no model can supply without reading the corpus.

| | Depth | File | Question asks for | Expected |
|---|---|---|---|---|
| **D1** | 2.6 % | `opencode.json` | the top-level `model` value | `zai/glm-5.2` |
| **D2** | 10.1 % | `patch-omlx-mtp.mjs` | the native window the comment gives Bonsai | `262,144` |
| **D3** | 29.8 % | `ai.sh` | the config key that is `False` so Bonsai's vision tower loads | `language_model_only` |
| **D4** | 53.4 % | `ai.sh` | the port it checks for a leftover opencode-mem web UI listener | `4747` |
| **D5** | 70.6 % | `ai.sh` | the value of `glm_degraded_context` | `24576` |
| **D6** | 95.3 % | `post-edit-check.js` | the filename of the generated wrapper tsconfig | `opencode-tsc-check.json` |

**Every answer is unguessable.** Two earlier candidates were cut for exactly this reason
before any request was sent: the top-level `default_agent` (`build`) and the log-prune age
(`14`) are both values a model could produce by convention without reading a line. Each
surviving answer is a value peculiar to this box — an uncommitted model id, a port, a
generated filename, a config key, two specific integers.

### Depth is measured from the question, not from the start

The question always sits **after** the whole corpus, so what matters to a sliding-attention
model is the distance from the question back to the needle:

- **D6 sits ~1,050 tokens from the end** — inside Muse's 2,048-token sliding window, so
  **all 52 layers** can see it. D6 is the **near control**. A model that fails D6 has a
  format or harness problem, not a long-range one.
- **D1–D5 sit 6,600 to 21,000 tokens back** — outside that window, so on Muse only the
  **13 full-attention layers** can reach them. D1–D5 are the **deep** set, and they are the
  measurement.

If the architectural worry in W21 is real, Muse fails on the deep set and passes the near
control. That specific shape — not a low total — is what confirms it.

## Serving conditions

Identical to [W14](../w14-capability/README.md), because a comparison to W14's result is the
whole point:

- One oMLX process, `ai.sh`'s own flags (hot 8 GB, SSD ≤ 25 GB, guard 48, concurrency 2), on
  **port 10082**. The port is the isolation: a live `opencode` session on 10081 runs
  `opencode-mem`, whose summarizer would load a second model mid-run and thrash the memory
  guard.
- Models load **one at a time**; the server restarts between them.
- **No `temperature` is sent**, mirroring `opencode.json`'s `"temperature": false`.
- `max_tokens: 8192` — production-faithful, and W14's amendment records what a lower cap
  manufactures. Reasoning tokens count against it.
- The **system message is byte-identical across every request** — instruction, then corpus.
  Only the short user question differs. That is what makes the door charge a once-per-model
  cost, and the probe records `prompt_tokens` and per-request wall so the claim is visible
  in the data rather than assumed.
- **2 repeats per needle.** W14 found all three models sample, whatever their
  `generation_config.json` claims, so a single run per needle is one sample and not a
  measurement.

12 runs per model: 10 deep (D1–D5 × 2) and 2 near control (D6 × 2).

## Grading

The model is asked for the **exact value only**. A run **passes** when the expected string
appears in the response's `content`, after normalising case, commas, quotes and whitespace.

- Grading reads `content` **only**. `reasoning_content` is recorded separately: a model that
  finds the fact while reasoning and then fails to state it has still failed to answer, and
  that distinction is worth keeping rather than averaging away.
- `finish_reason: length` is a **runaway**, counted as a fail and reported separately, as in
  W14.
- `UNKNOWN` is an allowed answer and is scored as a fail. It is offered so that a model has
  an honest alternative to inventing a value, and so a hallucinated constant is
  distinguishable from an admitted miss.

## The decision rule, fixed now

### Stage 1 — what the probe result means

Read on the **deep** set only, 10 runs per model:

| Probe result | Reading | Stage 2 |
|---|---|---|
| Muse ≥ 8/10 **and** no model beats Muse by ≥ 3 | No long-range retrieval fault found | Optional. If run, the **trimmed** suite: T1, T2, T4 |
| Muse ≤ 5/10 **or** a challenger beats Muse by ≥ 3 | A long-range fault is indicated | The **full** four-task suite at this size |
| Anything between | Indeterminate | The **trimmed** suite: T1, T2, T4 |

**A passed probe does not clear Muse Glimmer.** Retrieval is necessary, not sufficient.

### Stage 2 — what moves the default off Muse Glimmer

Chosen by the user before Stage 1 ran, and recorded here so it cannot be re-read afterwards:

1. **Margin.** Muse keeps bare `ai` unless a challenger solves **at least 3 more task-runs**
   than Muse. W14 declares a gap of one or two to be noise on 12 runs; 3 is the first margin
   outside that band.
2. **Collapse.** If Muse solves **under half** its runs while any challenger leads at all,
   the default moves to that leader — whatever the margin. This covers the case where Muse
   degrades badly and no challenger degrades well enough to clear a 3-gap.

Both rules read **solved task-runs** — pass@1 plus pass@2 — the same quantity W14 reported,
so the two results are directly comparable.

### What this asset may not do

As W14: **the result may not silently redraw the roster.** It records and it applies the
rule above. Anything beyond that is a fresh scoping decision for the map.

## Files

- [`build_corpus.py`](build_corpus.py) — builds `corpus.txt` and reports its size per
  tokenizer.
- [`probe.py`](probe.py) — runs the 12 requests against one model.
- [`run-probe.sh`](run-probe.sh) — restarts oMLX between models and runs all three.
- `probe-<model>.json` — raw per-run records.
- `RESULTS.md` — the tables.

---

## Outcome

*Added after the run. Nothing above this line changed.*

Stage 1 result: **36 of 36**, every model, every needle — see [RESULTS.md](RESULTS.md). The
first row of the Stage 1 rule fired: no long-range retrieval fault found.

Stage 2 was then run anyway, at the user's choice, in exactly the trimmed T1/T2/T4 shape
this file commits to. It needed **its own corpus** — see
[`build_corpus_s2.py`](build_corpus_s2.py) — because Stage 1's corpus contains the real
`scripts/patch-omlx-mtp.mjs` and `plugins/post-edit-check.js`, which *are* T2's and T4's
answers. Result and the applied floor: [RESULTS-long.md](RESULTS-long.md).
