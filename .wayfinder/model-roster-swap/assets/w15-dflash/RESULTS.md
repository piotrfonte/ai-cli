# W15 results — the DFlash drafter makes Muse Glimmer worse on every axis

Run 2026-08-12, `omlx 0.5.8.dev3` + `dflash-mlx 0.1.10+omlx.5`, port 10082, two server
runs minutes apart. Method and predictions: [README.md](README.md).

## The table

| Quantity | Baseline (DFlash off) | DFlash on | Change |
|---|---|---|---|
| Functional gate | PASS (`stop`, 123 ch) | PASS (`stop`, 120 ch) | — |
| Decode, 3 runs | 26.94 / 26.78 / 26.96 tok/s | **23.04 / 22.68 / 22.71** | **−15 %** |
| Cold prefill, 12,189 tok | 62.67 s ⇒ 194 tok/s | **75.59 s ⇒ 161 tok/s** | **+21 %** |
| Warm repeat, same prompt | 10.58 s, `cached=10,240` | **86.60 s, `cached=0`** | **8.2× worse** |
| Two requests together | 25.94 s (single 19.56 s) | **51.34 s** (single 21.36 s) | overlap lost |
| Peak process RSS | 11.44 GB | 15.33 GB | +3.9 GB |
| Median process RSS | 10.79 GB | 15.31 GB | +4.5 GB |

Baseline reproduces [W7](../../tickets/07-serve-check-muse.md) closely — 26.8–27.0 tok/s
against its 26.0–27.1, and 194 tok/s prefill against its 187–200 — so the two runs are
comparable and W7's numbers stand.

## It engaged. That is the point.

`load_vlm_mtp_drafter` soft-fails, and this map already records a drafter that was inert
for weeks, so the rate alone proves nothing. The log proves it:

```
omlx.model_discovery  - Treating HF cache model as MLX-compatible speculative-decoding
                        helper: meta-models/Muse-Glimmer-30B-assistant
omlx.engine_pool      - DFlash enabled for Muse-Glimmer-30B-4bit,
                        draft=meta-models/Muse-Glimmer-30B-assistant
omlx.engine.dflash    - DFlashEngine loaded: target=…/Muse-Glimmer-30B-4bit,
                        draft=…-assistant, max_ctx=unlimited, fallback=vlm,
                        l1_cache=True, l2_cache=False, draft_window=1024,
                        draft_sink=64, verify=adaptive
[dflash] prefix cache enabled (max_entries=4, max_bytes=8589934592)
```

No fallback to the VLM engine, no precision-pairing warning, no drafter error. DFlash
served every request in run B. **A slower number from a working drafter is a real result,
not a misconfiguration.**

The one thing not measured is the **acceptance ratio**. `get_speculation_stats()` is served
only from `/admin/api/activity`, which returns 401 without a session cookie, and the only
way past it is `auth.skip_api_key_verification` in the user's own `~/.omlx/settings.json`.
That flag was left alone. So *why* acceptance was poor is unknown; *that* the drafter ran
and lost is not.

## The prefix cache never inserts — this is the finding that matters

Across run B's nine requests: `entries=0/4  hits=0+0  misses=9  insertions=0
prefill_tokens_saved=0`. Not a low hit rate — **zero insertions**.

The obvious confound was that measure.py's long prompts run at `max_tokens: 1`, and dflash
publishes its snapshot from the generation loop. `confirm-cache.py` closes it:

| Turn | Prompt | Cached | Completion | Time |
|---|---|---|---|---|
| 1 — cold, **real generation** | 12,189 | 0 | 367 | 93.71 s |
| 2 — same prompt again | 12,189 | **0** | 1 | **77.20 s** |

A full generation, then the identical prompt, and the repeat still re-prefills from
scratch. The cache does not insert.

oMLX *does* wire the writer — `PrefixCacheFlow.for_request` builds a `SnapshotService`
(`omlx/engine/dflash.py:1134`) and it is passed into the runtime — so this is not a missing
integration at the obvious level. The gate that declines to publish was not identified, and
identifying it was out of scope for this ticket.

**What it costs the user:** DFlash replaces the engine, so oMLX's two-tier paged cache is
not in the path, and dflash's own L1 replaces it with nothing. [W13](../../tickets/13-roster-after-prefill.md)
established that Muse's ~64 s prefill is a **door charge paid once per directory visit**,
because turn 2 re-uses the cached prefix. Under DFlash that is false: **every turn pays the
full prefill again.** A ten-turn session pays ~13 minutes of prefill instead of ~64 s plus
change. L2 (SSD) is off by default and would not help — L2 spills what L1 admits, and L1
admits nothing.

## Concurrency: the overlap is lost

Two identical decode requests fired together took **51.34 s**, against a single-request mean
of 21.36 s — 2.4×, so they serialized and paid overhead on top. The baseline pair took
25.94 s against a single-request mean of 19.56 s — 1.33×, real overlap.

This is structural, not tuning: `DFlashEngine` bypasses the scheduler and runs generation on
the single MLX executor behind an `_active_request` flag. `--max-concurrent-requests 2`
exists so the opencode-mem summarizer can overlap a coding turn; under DFlash it cannot.

## Memory: the drafter is cheap, the machinery is not

Measured directly with the server down (`drafter-cost.py`), which is the only honest figure —
`engine_pool` logs `actual: 2.52GB` at load because the target loads lazily:

| Drafter | Active memory |
|---|---|
| `w4a16:gs64` — what run B used | **1.34 GB** |
| unquantized BF16 | 4.76 GB |

So the quant flag worked, and saved 3.4 GB. Note the prediction in README §2 held: the flag
must be asked for, because `engine_pool` never consults the registry's `w4` default.

But peak RSS rose by 3.9 GB while DFlash **does not load the ~3.63 GB vision tower** (it
uses dflash's text-only module — README §3 confirmed). Drafter 1.34 GB minus tower 3.63 GB
should have been a net *saving*. The ~6 GB gap is DFlash's own verify and hidden-capture
buffers. Nothing came close to the guard's 40.8 GB soft threshold, so memory is not the
reason to reject this — it just is not the saving the architecture suggested.

## Two smaller findings

- **Output became deterministic.** All three DFlash decode runs returned exactly 473
  completion tokens; the baseline returned 518 / 621 / 387 on the same prompt. Worth noting
  against [W14](../../tickets/14-capability-comparison.md), which found oMLX does not honour
  `do_sample` and all three models sample at their defaults.
- **Drafter resolution hits the network at model load.** The log shows a live
  `GET huggingface.co/api/models/meta-models/Muse-Glimmer-30B-assistant/revision/main`
  before the engine starts, because `_resolve_local_model_path` calls `snapshot_download`
  on the repo id. A `dflash_draft_model` pointing at a local path would avoid it.
- **No oMLX symlink was needed.** oMLX found the drafter in the HF cache by itself
  (`hf_cache_enabled`), classified `muse_glimmer_assistant` as a helper, and kept it out of
  `/v1/models`. The roster still lists three models.

## Disk

The KV cache did not grow across either phase (21 G → 22 G, and that G predates run B):
Muse writes almost nothing to the SSD tier, exactly as W7 found, and DFlash's L2 is off.
**No pruning was done**, deliberately — it would have destroyed GLM's and Bonsai's warm
blocks to buy headroom this measurement never needed. Free disk is **24 GiB (98 % full)**,
4.8 GB of which is the drafter downloaded for this ticket.

## Files kept with this asset

`results-baseline.json`, `results-dflash.json`, `results-confirm-cache.json` — raw client
numbers. `logs/` — the full server log of each of the three runs, plus a grepped excerpt of
the lines that prove engagement. `drafter-cost.py` — the memory measurement, run with the
server down.

## Verdict

The success bar was "decode that closes the gap to Bonsai's ~38 tok/s, proven engaged, at a
memory cost that does not threaten the guard". Decode went the wrong way, prefill went the
wrong way, prefix reuse was destroyed and concurrency serialized. **Leave DFlash off.**
`set-dflash.py off` was re-run after the measurement, so `~/.omlx/model_settings.json` holds
no `dflash_*` key for this model.
