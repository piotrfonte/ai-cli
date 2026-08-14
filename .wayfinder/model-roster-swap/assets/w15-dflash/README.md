# W15 asset — does the DFlash drafter move Muse Glimmer's numbers?

Measurement that resolves
[Try the DFlash drafter on Muse Glimmer](../../tickets/15-dflash-drafter-muse.md).

**Written before the run.** Nothing below changed after the first request went out.

## What this measures

Whether oMLX's DFlash speculative-decode path lifts `mlx-community/Muse-Glimmer-30B-4bit`
from its measured **26.0–27.1 tok/s** decode, at a memory cost that does not threaten the
48 GB guard, and **provably engaged** rather than merely faster-looking.

## What the code says before any measurement

Read from `omlx 0.5.8.dev3` and `dflash-mlx 0.1.10+omlx.5` on this box:

1. **The drafter is `meta-models/Muse-Glimmer-30B-assistant`**, named in
   `dflash_mlx/runtime/registry.py` against target family `muse_glimmer_swa`. It is
   2.56 B parameters, **BF16, 5.1 GB** on the Hub, `model_type: muse_glimmer_assistant`.
   oMLX classifies that type as a **helper**, so it never appears in `/v1/models` — the
   roster stays three models.
2. **The registry's `w4` default does not reach oMLX.** `W4_DEFAULTS` is consumed by
   dflash's own CLI. `engine_pool` passes `dflash_draft_quant_enabled` straight from
   `model_settings`, and `DFlashEngine.start()` quantizes **only when that flag is true**.
   Left unset, the drafter loads BF16 at its full 5.1 GB. The quant must be asked for.
3. **DFlash replaces the engine, it does not decorate it.** `engine_pool` builds
   `DFlashEngine` *instead of* the VLM engine, and `load_target_bundle` loads dflash's own
   **text-only** module for this model. So the ~3.63 GB vision tower W7 measured should
   not load at all — the drafter may be partly self-financing.
4. **The oMLX paged cache is not DFlash's cache.** DFlash carries a private L1 (RAM,
   default on, 4 entries / 8 GiB) and L2 (SSD, **default off**) prefix cache, because its
   snapshots hold draft state oMLX never tracks. So W7's 3.5 s warm restore is not
   automatically inherited, and with L2 off nothing survives a restart.
5. **DFlash bypasses the scheduler.** It has its own prefill guard and runs generation on
   the single MLX executor behind an `_active_request` flag, so concurrency is expected to
   serialize rather than batch. Constraint: `--max-concurrent-requests 2` exists so the
   opencode-mem summarizer can overlap a coding turn.

Points 2–5 are predictions from source. The run tests them.

## Serving conditions

One oMLX process, `ai.sh`'s flags, on **port 10082** — the same isolation W14 used: a live
`opencode` elsewhere on this box runs opencode-mem, whose summarizer would otherwise load a
second model into this guard mid-measurement.

```
--paged-ssd-cache-dir ~/.omlx/cache --paged-ssd-cache-max-size 25GB
--hot-cache-max-size 8GB --memory-guard-gb 48 --max-concurrent-requests 2
```

**Two server runs, one variable.** Run A is the baseline with DFlash off; run B enables it.
Both run in this session, minutes apart, on the same box state — W7's numbers are the
external check, not the comparison.

`max_tokens: 8192` throughout, per constraint 9 as W14 raised it. No `temperature` is sent,
so oMLX falls back to the model's own `generation_config.json` — the configuration production
actually runs. `max_context_window: 69632` stays pinned as `patch-omlx-mtp.mjs` writes it.

## Settings under test (run B)

Written to `~/.omlx/model_settings.json` under **both** the two-level id and the bare
directory leaf, because oMLX resolves a request to the leaf and keys settings by it:

```json
{ "dflash_enabled": true,
  "dflash_draft_model": "meta-models/Muse-Glimmer-30B-assistant",
  "dflash_draft_quant_enabled": true }
```

`dflash_draft_quant_enabled` alone yields `w4a16:gs64` from `_build_quant_spec`'s own
fallbacks — the registry's `w4` for this model, asked for explicitly per point 2. Every
other `dflash_*` knob keeps its default, including **L2 off**, so run B changes the decode
path and nothing else.

## The six measurements, per run

| # | Measures | Method |
|---|---|---|
| 1 | Functional gate | `finish_reason: stop` **and** non-empty `content`, at `max_tokens: 8192`, on a real coding prompt |
| 2 | Resident memory | oMLX's own figure via `/admin/api/activity`, plus process RSS |
| 3 | **Decode** | Short prompt (~60 tok), 3 runs. `completion_tokens / (elapsed − prefill)`, where prefill is that same prompt measured at `max_tokens: 1`. Prefill is ~0.3 s here, so this is decode |
| 4 | Prefill door charge | CLAUDE.md as the prompt (~12.8k tok) at `max_tokens: 1`, unique nonce so it is genuinely cold |
| 5 | Warm repeat | The same 12.8k prompt again, same server — does a private L1 hit replace the paged-cache hit? |
| 6 | Concurrency | Two identical decode requests fired together; wall time against the serial pair |

Engagement is proven from `/admin/api/activity` — `accepted_draft_tokens`,
`acceptance_ratio`, `cycles` — and from `dflash` / `speculative` lines in the server log.
**A rate that merely looks better is not proof**: `load_vlm_mtp_drafter` soft-fails, and
this map already records one drafter that was silently inert for weeks.

## Measurement rules carried from the ticket

- Prefill is isolated with `max_tokens: 1`. **Never** subtract decode from the server log's
  `tok/s` line — builds report it differently.
- Every request carries a unique nonce where coldness matters.
- Disk was checked before the run rather than pruned blind; see RESULTS.md.

## What counts as success

Decode that closes the gap to Bonsai's ~38 tok/s, proven engaged, with resident memory
clear of the guard's 40.8 GB soft threshold. Anything less and Muse Glimmer keeps W7's
numbers — an acceptable outcome. This is a lever to try, not a rescue the roster needs.

## Files

- `set-dflash.py` — flips the settings block on/off, both key spellings, idempotent.
- `measure.py` — the six measurements; writes `results-<tag>.json`.
- `run-all.sh` — server lifecycle for both runs.
- `RESULTS.md` — what came back.
