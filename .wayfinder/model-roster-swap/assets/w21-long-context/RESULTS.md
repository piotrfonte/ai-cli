# W21 Stage 1 — result

Run 2026-08-13, `omlx 0.5.8.dev3`, port 10082, one model per server run, `max_tokens: 8192`,
no `temperature` sent. Rubric and decision rule in [README.md](README.md), written before the
first request.

## Headline: every model swept, so the probe cannot rank them

| Model | Deep (D1–D5 × 2) | Near control (D6 × 2) | Strict answers | Runaways | Errors |
|---|---|---|---|---|---|
| Muse Glimmer 30B 4-bit | **10/10** | 2/2 | 12/12 | 0 | 0 |
| GLM 4.7 Flash 6-bit | **10/10** | 2/2 | 12/12 | 0 | 0 |
| Ternary Bonsai 27B 2-bit | **10/10** | 2/2 | 12/12 | 0 | 0 |

**36 of 36.** Every answer was *strict* — the exact value and nothing else, no prose, no code
fence, no hedge. Not one model answered `UNKNOWN`, and not one invented a value.

Applying the pre-registered rule: Muse scores 10/10 and cannot be beaten by 3, so the first
row holds — **no long-range retrieval fault found**, and Stage 2 is optional rather than a
defence of the default.

### The specific worry that made this ticket urgent is dead

W21 predicted Muse would fall furthest, because `layer_types` runs 3 `sliding_attention` :
1 `full_attention` at `sliding_window: 2048`, so only **13 of 52 layers** ever see the whole
window. The probe was built to expose exactly that: D6 sits ~1,050 tokens back, inside the
sliding window where all 52 layers reach it, while D1–D5 sit **6,600 to 21,000 tokens back**,
where only the 13 full-attention layers can.

The predicted shape is a deep-set failure with a passing near control. **It did not appear.**
Muse answered the 21,000-token-deep needle as reliably as the 1,050-token one, twice each.
Thirteen full-attention layers are enough to retrieve an exact string at this distance.

### And the probe hit a ceiling, which is its own limitation

A 36/36 sweep carries no ranking information. The probe was built to be cheap and
discriminating; it turned out to be cheap and **saturated**. It rules out a gross retrieval
failure in any model. It cannot say which model retrieves *better*, because none of them
failed once.

## Cost, and a correction to the map's cache rule

| Model | Prompt tokens | Cold (1st request) | Warm median | Warm max | Total wall |
|---|---|---|---|---|---|
| Muse Glimmer | 21,716–21,739 | 130.4 s | 26.0 s | 31.8 s | **400.7 s** |
| GLM 4.7 Flash | 22,025–22,049 | 92.2 s | **20.6 s** | 189.4 s | 487.5 s |
| Ternary Bonsai | 23,328–23,351 | 203.8 s | 23.6 s | 34.4 s | 461.5 s |

Cold includes the model load. Every warm request restored the constant prefix.

**The door charge is confirmed once per model, on all three.** W13 measured this on Bonsai
alone; it now holds across the roster at ~22k. The cost premise in W21 — "every repair turn
re-prefills", so the suite is "hours, not minutes" — is wrong.

### `cached_tokens` does not round to 2048 on every model

W13 recorded that `cached_tokens` "rounds down to a 2048-token block", and `CLAUDE.md` carries
that as a general rule. It is **model-dependent**:

| Model | `cached_tokens` observed | Block | Fresh tokens re-prefilled per turn |
|---|---|---|---|
| Muse Glimmer | 20,480 | 2,048 (10×) | 1,236–1,259 |
| Ternary Bonsai | 22,528 | 2,048 (11×) | 800–823 |
| **GLM 4.7 Flash** | 21,760 / 22,016 | **256** (85×, 86×) | **9–289** |

GLM's cache matches at a **256-token granularity**, so it re-prefills up to 4.4× less
already-seen prefix per turn than Muse. W13 measured Bonsai and generalised; the rule holds
for the two 2048-block models and understates GLM's cache by a factor of eight.

### Bonsai's cold prefill ran slower than its own published rate

203.8 s for 23,329 tokens is ~115 tok/s including a ~2.9 s load, against the ~194 tok/s W6
measured and the ~167 tok/s implied by W7's 25k rung. **Recorded, not explained.** The SSD
cache stood at its 25 GB cap when the run started, so eviction during block writes is a
candidate, but nothing here isolates it. It does not affect the verdict — every warm request
behaved normally.

### GLM is the fastest model here and finished last

GLM holds the lowest cold prefill (92.2 s) and the lowest warm median (20.6 s), and still
posts the **longest total wall of the three**. One request took **189.4 s and burned 15,681
reasoning characters** on a needle it had answered in 34.2 s with 2,932 characters on the
previous repeat.

| Model | Total reasoning chars | Warm median → max |
|---|---|---|
| Muse Glimmer | 12,478 | 26.0 → 31.8 s (1.2×) |
| Ternary Bonsai | 10,570 | 23.6 → 34.4 s (1.5×) |
| GLM 4.7 Flash | **33,711** | 20.6 → **189.4 s (9.2×)** |

This is W14's and W19's finding reproduced at long context, in a milder form: **zero
runaways, but one near-runaway**, on a question every model answered correctly. GLM spends
2.7–3.2× the reasoning of the other two for an identical score, and its per-request wall is
unpredictable.

Per solved run — W18's metric, computed here only because every model solved everything:

- Muse Glimmer **0.56 min**, Ternary Bonsai 0.64 min, GLM 4.7 Flash 0.68 min.
- **Stated honestly: drop GLM's single outlier and it leads at 0.45 min.** One sample decides
  this ranking, so it is an observation and not a result. It is recorded because the outlier
  is the very behaviour W14 measured at 4/12, not a stray.

## What this result does and does not settle

**Settles:** no model on this roster loses an exact fact across ~22k tokens of real repository
source, and Muse's sliding-attention structure does not cost it retrieval at that distance.
The prefix-cache economics that make a long-context suite affordable are confirmed on all
three models.

**Does not settle — and this was written before the run, not after:** retrieval is necessary,
not sufficient. A model can quote a constant correctly and still write worse code over a long
context. Nothing here measures **writing or repairing code** at ~22k, which is the question
[W21](../../tickets/21-long-context-capability.md) actually asks. That is Stage 2.

**Also not settled:** the probe asks for one fact per request. Real agentic work needs several
facts held at once, combined, and acted on. A single-needle probe is the weakest form of the
test, chosen for cost.
