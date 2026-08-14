---
id: W15
title: Try the DFlash drafter on Muse Glimmer
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: [W13]
---

## Question

**Does the DFlash drafter move Muse Glimmer's numbers enough to matter?**

Muse Glimmer stays on the roster ([W13](13-roster-after-prefill.md)), so the one
untried lever it has now has a job. This oMLX build makes DFlash speculative decode
first-class — a whole `dflash_*` settings family, an L1/L2 prefix cache of its own, and
a drafter **for this model specifically**. It is the only differentiator Muse Glimmer
has that Bonsai does not.

The first cut deliberately left it off, for the same reason MTP was left off: a run that
changes both the model and the decode path cannot attribute a bad result. That reason
has now expired — the baseline exists.

### The baseline this measures against

From [W7](07-serve-check-muse.md), at defaults, with **zero** `dflash`, `mtp` or
`speculative` lines in the log:

| Quantity | Value |
|---|---|
| Prefill, 12,882 tok | **64.46 s** (187–200 tok/s) |
| Decode | **26.0–27.1 tok/s** — slowest on the roster |
| Resident | 18.59 GB |
| Warm restore, 25 k prefix | 3.52–3.79 s |

### What to establish

1. **Which drafter, and what it costs.** Find what oMLX ships for this model, its size
   on disk, and its resident cost. Muse Glimmer is already the second-heaviest profile
   at 18.59 GB, so a drafter that pushes it toward the memory guard's soft threshold
   (40.8 GB at a guard of 48) trades one problem for another.
2. **Whether it engages at all.** `load_vlm_mtp_drafter` **soft-fails** — CLAUDE.md
   already records this for Gemma. A misconfigured drafter is indistinguishable from
   "the model is just slow". **Prove engagement from the server log**, not from a rate
   that looks better.
3. **Decode, measured.** Speculative decode lifts decode. Expect nothing on prefill.
4. **Prefill, measured anyway** — cheaply, at `max_tokens: 1` — to confirm the 64.5 s
   door charge is unchanged. If DFlash's own L1/L2 prefix cache interacts with the
   paged cache, that is a finding worth having.
5. **Whether it survives concurrency.** `--max-concurrent-requests 2` exists so the
   opencode-mem summarizer can overlap a coding turn. MTP on the old `-l` profile
   engaged only "when batch rows align". Check whether DFlash degrades the same way.

### Settings go where oMLX reads them

Any `dflash_*` setting belongs in `~/.omlx/model_settings.json` via
`scripts/patch-omlx-mtp.mjs`, keyed under **both** the two-level id and the bare
directory leaf. An entry under the two-level id alone is silently never consulted —
that bug made MTP inert for `-l` for weeks. Settings are read at **model load**, so a
change needs a server restart.

### Measurement rules

Isolate prefill with `max_tokens: 1`. **Never subtract decode from the server log
line** — builds report `tok/s` differently and the arithmetic silently disagrees.
Prune the KV cache before measuring; the disk sits near full.

### What counts as success

A decode rate that closes the gap to Bonsai's ~38 tok/s, proven engaged, at a memory
cost that does not threaten the guard. Anything less and Muse Glimmer keeps its current
numbers, which is an acceptable outcome — this ticket is a lever to try, not a rescue
the roster depends on.

### W14 raises the value of this ticket

Written when Muse Glimmer was the roster's weakest-looking profile — kept only because
nothing had tested capability. [W14](14-capability-comparison.md) has now tested it, and
**Muse writes the best code of the three** (9/12 pass@1 against GLM's 6 and Bonsai's 5),
with zero runaway turns and the lowest token spend.

So the one thing standing between the best coder on the roster and the default slot is
**decode speed at 26 tok/s** — exactly what this ticket attacks. That makes W15 a lever on
[Decide the default profile now that capability is measured](18-default-after-capability.md),
not just a curiosity: closing the gap to ~38 tok/s materially changes W18's trade. The
converse also holds — if the drafter does not engage, W18 decides against an unchanged
26 tok/s.

### Related

- [Serve-check Muse Glimmer 30B 4-bit and measure it](07-serve-check-muse.md) — the
  baseline, and the confirmation that no drafter was engaged for it.
- [Decide the roster now that Bonsai prefills at ~200 tok/s](13-roster-after-prefill.md)
  — why Muse Glimmer stays.

## Resolution

**No. The drafter engages, and it makes this model worse on every axis. DFlash stays off.**

Two server runs minutes apart, same box state, one variable. Method and predictions were
written before the run: [assets/w15-dflash](../assets/w15-dflash/). Full numbers:
[RESULTS.md](../assets/w15-dflash/RESULTS.md).

| Quantity | Baseline | DFlash on | Change |
|---|---|---|---|
| Decode, 3 runs | 26.94 / 26.78 / 26.96 tok/s | **23.04 / 22.68 / 22.71** | **−15 %** |
| Cold prefill, 12,189 tok | 62.67 s ⇒ 194 tok/s | 75.59 s ⇒ 161 tok/s | +21 % |
| Warm repeat, same prompt | 10.58 s, `cached=10,240` | **86.60 s, `cached=0`** | 8.2× worse |
| Two requests together | 25.94 s (single 19.56 s) | 51.34 s (single 21.36 s) | overlap lost |
| Peak RSS | 11.44 GB | 15.33 GB | +3.9 GB |

The baseline reproduces [W7](07-serve-check-muse.md) — 26.8–27.0 tok/s against 26.0–27.1,
194 tok/s prefill against 187–200 — so the comparison is sound and W7's numbers stand.

### 1. It engaged, and the log proves it

Point 2 of the ticket demanded proof from the log rather than a rate that looks better.
`omlx.engine_pool - DFlash enabled for Muse-Glimmer-30B-4bit, draft=meta-models/Muse-Glimmer-30B-assistant`,
then `DFlashEngine loaded: … max_ctx=unlimited, fallback=vlm, l1_cache=True, l2_cache=False,
draft_window=1024, draft_sink=64, verify=adaptive`. No fallback to the VLM engine, no
precision-pairing warning, no drafter error. **A slower number from a working drafter.**

The **acceptance ratio is the one thing not measured.** `get_speculation_stats()` is served
only by `/admin/api/activity`, which 401s without a session cookie; the only way past it is
`auth.skip_api_key_verification` in the user's own `~/.omlx/settings.json`, and that flag
was left alone. So *why* acceptance was poor is unknown. *That* the drafter ran and lost is
not.

### 2. The finding that outranks the decode number: the prefix cache never inserts

Nine requests in run B: `entries=0/4  hits=0+0  misses=9  insertions=0
prefill_tokens_saved=0`. Not a poor hit rate — **zero insertions**. The obvious confound was
that the long prompts ran at `max_tokens: 1`; `confirm-cache.py` closed it — a cold 12,189
prompt with a **real 367-token generation**, then the identical prompt again, still returned
`cached=0` and re-prefilled in 77.20 s.

DFlash replaces the engine, so oMLX's two-tier paged cache is out of the path, and dflash's
own L1 replaces it with nothing. **This inverts [W13](13-roster-after-prefill.md)'s central
finding.** The ~64 s prefill is a door charge paid once per directory visit *because turn 2
re-uses the prefix*; under DFlash every turn pays it again. A ten-turn session costs ~13
minutes of prefill instead of ~64 s plus change. L2 is off by default and cannot help — it
spills what L1 admits, and L1 admits nothing.

oMLX does wire the writer (`PrefixCacheFlow.for_request` builds a `SnapshotService`,
`omlx/engine/dflash.py:1134`), so this is not a missing integration at the obvious level.
The gate that declines to publish was not identified; that was out of scope here and is now
map fog.

### 3. Concurrency serializes, as predicted from source

Two requests together took 51.34 s against a 21.36 s single-request mean — 2.4×, so they
serialized and paid overhead. The baseline pair took 25.94 s against 19.56 s — 1.33×, real
overlap. Structural: `DFlashEngine` bypasses the scheduler and runs generation on the single
MLX executor behind an `_active_request` flag. `--max-concurrent-requests 2` exists so the
opencode-mem summarizer can overlap a coding turn; under DFlash it cannot.

### 4. What it costs, per point 1

The drafter is `meta-models/Muse-Glimmer-30B-assistant` — 2.56 B params, 5 layers, hidden
6656, `block_size 16`, reading target layers [1, 13, 25, 37, 49]. **5.1 GB BF16 on the Hub,
4.8 GB on disk.** Measured with the server down, because `engine_pool`'s `actual: 2.52GB`
is a lazy figure:

| Drafter | Active memory |
|---|---|
| `w4a16:gs64` — what this run used | **1.34 GB** |
| unquantized BF16 | 4.76 GB |

**The quant must be asked for.** `W4_DEFAULTS` in dflash's registry feeds dflash's own CLI;
`engine_pool` passes `dflash_draft_quant_enabled` straight from `model_settings` and the
engine quantizes only when it is true. Left unset the drafter costs 4.76 GB for nothing.

Peak RSS still rose 3.9 GB even though DFlash **does not load the ~3.63 GB vision tower**
(it uses dflash's text-only module). Drafter minus tower should have been a net saving; the
~6 GB gap is DFlash's own verify and hidden-capture buffers. Nothing approached the guard's
40.8 GB soft threshold, so **memory is not the reason to reject this** — it simply is not
the saving the architecture suggests.

### 5. Smaller findings

- **Output went deterministic.** All three DFlash decode runs returned exactly 473
  completion tokens; the baseline returned 518 / 621 / 387 on the same prompt. Set against
  [W14](14-capability-comparison.md), which found oMLX does not honour `do_sample`.
- **Drafter resolution hits the network at model load** — a live
  `GET huggingface.co/api/models/…/revision/main` before the engine starts, because
  `_resolve_local_model_path` calls `snapshot_download` on the repo id. A local path in
  `dflash_draft_model` would avoid it.
- **No symlink was needed.** oMLX found the drafter in the HF cache itself, classified
  `muse_glimmer_assistant` as a **helper**, and kept it out of `/v1/models`. The roster
  still serves three models and no others.
- **No pruning was done, deliberately.** The KV cache did not grow across either phase —
  Muse writes almost nothing to the SSD tier (W7) and DFlash's L2 is off — so pruning would
  only have destroyed GLM's and Bonsai's warm blocks. Free disk is **24 GiB (98 % full)**,
  of which 4.8 GB is the drafter this ticket downloaded.

### 6. What this hands to W18

The ticket's own converse now applies:
[Decide the default profile now that capability is measured](18-default-after-capability.md)
**decides against an unchanged 26 tok/s**, and slightly worse than that — the one lever Muse
Glimmer had is spent. Option B (make Muse the default) costs what W14 already priced, with
no speculative relief available.

### 7. Settings left clean

`set-dflash.py off` was re-run after the measurement, so `~/.omlx/model_settings.json` holds
no `dflash_*` key for this model — only the `max_context_window: 69632` rail. `DESIRED` in
`scripts/patch-omlx-mtp.mjs` is unchanged: no roster model pins a speculative setting.

**The drafter weights are still on disk** (4.8 GB, `~/.cache/huggingface/hub/models--meta-models--Muse-Glimmer-30B-assistant`).
Deleting them is the user's call, as it was for the GGUF in [W10](10-remove-muse-gguf.md).
