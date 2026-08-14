---
labels: [wayfinder:map]
slug: model-roster-swap
charted: 2026-08-11
---

# Map: Local model roster swap

## Destination

`ai` serves **three MLX models and no others**, each proven to carry a real coding
turn, with **one copy of every weight file shared between oMLX and LM Studio**:

| Profile | Model | On disk |
|---|---|---|
| bare `ai` (also `--bonsai`) | `prism-ml/Ternary-Bonsai-27B-mlx-2bit` | 7.9 GB, present |
| `--muse` | `mlx-community/Muse-Glimmer-30B-4bit` | 18.99 GB, present |
| `--glm` | `lmstudio-community/GLM-4.7-Flash-MLX-6bit` | 23 GB, present |

**The default has moved twice.** W18 took it from GLM to Muse Glimmer on measured capability
at short prompts; **W23 took it from Muse to Bonsai on 2026-08-14**, after W21 found that
capability no longer separates the three at agentic length while the cost difference stayed.
The shape of the destination is unchanged — three models, one copy of every weight, changed
in place — only which flag serves which model.

Qwen 3.6 35B-A3B (both quants), Gemma 4 12B and Macaw are gone. The change is made
in place: `ai.sh`, `opencode.json`, `scripts/*.mjs` and `CLAUDE.md` all updated.

**Destination reached 2026-08-13.** All 23 tickets are closed and the frontier is empty.
The roster, the flags, the caps, the patches and the docs are all in the tree. What remains
on this map is fog only — see **Not yet specified**, where the live entries are whether a
larger suite could separate the three models at agentic context, and the fact that costs
reasoned before W21 were derived at short-context decode rates.

**The destination was re-opened once, the same day it was reached.** W22 found the default
model's tool calls arriving corrupt in a real opencode session — four `⚙invalid` errors and
raw XML where four `bash` calls should have been. That lands directly on "proven to carry a
real coding turn", so it was a ticket on this map rather than a fresh effort. It is fixed by
a fourth oMLX source patch. **The lesson outlives the fix: no check on this map tested the
wire format of a tool call under agentic conditions.** W7's serve check asserts that *a* tool
call parses and W14 graded the code models write, both at short prompts with simple tool use.

## Notes

**Domain.** A Bash launcher (`ai.sh`) plus opencode config, driving a local oMLX
server on an M4 Max / 64 GB Mac. Communicate in ASD-STE100 Simplified Technical
English. Consult `/grilling` and `/domain-modeling` when a ticket needs judgement.

**Execution override.** This map *does* the work, not only the decisions. The
destination is a change made in place.

**Validate with** `bash -n ai.sh`, `python3 -m json.tool opencode.json >/dev/null`,
`node --check scripts/<file>.mjs`, and `node scripts/patch-omlx-mtp.mjs /tmp/ms.json`
against a throwaway path.

**Standing constraints, fixed while charting (2026-08-11):**

1. oMLX stays the runtime for `ai`. LM Studio stays installed and is driven
   separately; it does not replace oMLX.
2. **Weight sharing is a blocker, not a bonus.** One copy on disk per model. **W10
   finds the sharing is one-directional for Muse Glimmer**: one copy, but only oMLX
   reads it, because LM Studio's mlx_vlm 0.6.5 has no `muse_glimmer` module.
3. The weight store is LM Studio's: `~/.cache/huggingface/hub/<org>/<repo>` — flat
   dirs, *not* HF's `models--org--repo/snapshots/<sha>/`. oMLX reaches it by symlink
   from `~/.omlx/models/<org>/<repo>`, so `bge-m3` stays where it is.
4. **The user downloads models by hand in LM Studio.** `_ensure_model` loses its
   `hf download` path; it verifies, symlinks, and otherwise fails loudly by name.
5. The oMLX stack upgrades **in place, one build** — `mlx`, `mlx-lm`, `mlx-vlm` and
   `omlx` all move. No second checkout, no second venv.
6. ~~GLM 4.7 Flash is the bare `ai` default.~~ **W18 replaces it: Muse Glimmer serves bare
   `ai`, and GLM moves to `--glm`.** The deciding metric is **minutes per solved task**
   (Muse 3.46, GLM 3.83, Bonsai 4.09), not tok/s — raw speed flatters a model that fails,
   and GLM spent 18.2 of its 23.0 measured minutes producing nothing usable. Old flags
   (`-l`, `-g`, `--macaw`) stay hard errors, never silent remaps. `--muse` survives as an
   explicit alias for the default, because it names a model that stays. **The default
   stays one fixed model** — no `AI_PROFILE` override, so the choice cannot go unmade.
   W18 also found and fixed a trap this swap would have shipped silently: `ai.sh` tracked
   the profile as the literal string `"default"`, which the GLM MLA fail-safe keyed on,
   so the guard would have followed the sentinel onto the wrong model.
7. Context starts at **65,536 for all three** for a clean comparison; raise per model
   only after measurement. **W5 breaks this for GLM** — oMLX's 7× MLA KV over-count
   makes 65,536 unreachable, and 20k is the measured safe point. **W6 and W7 both reach
   65,536** with no warning at all, so for those two a cap is a latency choice, not a
   memory one — cold prefill of a full window costs **7 m 24 s** (Bonsai) and
   **6 m 54 s** (Muse Glimmer). **W13 settles those two: Bonsai and Muse keep the flat
   65,536**, because a session grows one cached turn at a time and only a single
   pathological turn pays the full-window cost.
   **W12 closes the constraint, and breaks it for good: GLM declares 32,768.** The
   over-count is fixed (7.08× → exact), and 65,536 is *still* unreachable, because the
   binding constraint was never KV — it is the prefill activation transient against
   Apple's Metal cap. 45,072 tokens force-stops mid-prefill and unloads the model;
   40,976 passes in 266 s but only by winning a race with the adaptive throttle. **A
   flat number across three models is not available on this box.** ~~Headroom levers that
   might raise it are [Buy prefill headroom for GLM](tickets/17-glm-prefill-headroom.md).~~
   **W17 closes those levers and re-founds the number on a firmer reason: time, not
   memory.** The user waits at most 120 s for a cold open; prefill grows as O(n²); a
   120 s budget lands at ~32,311 tokens, so 32,768 is within 1.5 % of the patience
   boundary. Peak RSS on every passing rung read 23–28 GB against a 51.84 GiB cap, so
   memory had headroom the whole time. **This reason is stable** — unlike the memory one,
   it does not move if a future oMLX fixes the guard, and it applies to every profile:
   Muse reaches only ~22,800 tokens in the same 120 s.
8. **MTP stays off** in the first cut, even though GLM carries an MTP head. **W15 closes
   the sibling path on measurement, not caution**: DFlash speculative decode engages on Muse
   Glimmer and costs 15 % of decode, 21 % of prefill and all prefix reuse, so every roster
   model now runs a plain decode path — GLM and Bonsai by default, Muse by measurement.
   oMLX rejects `mtp_enabled` and `dflash_enabled` together at construction, so the two were
   never combinable anyway.
9. Model settings (thinking, reasoning strength) stay at their defaults until
   measurement proves one broken. **W19 tested that clause against GLM and it held:
   the one pin the roster had a measured reason to try was tried, and reverted.**
   Pinning `enable_thinking: false` removed every runaway (4/12 → 0/12) and cut the
   suite from 23.0 to 1.9 minutes, yet solved fell 6/12 → 4/12 — GLM's reasoning is
   what produces its correct answers. So the roster still pins **nothing**, now by
   measurement rather than by default. **W11 sharpens the word "nothing"**: the roster
   pins no *behaviour*, but it does pin one *safety rail* per model —
   `max_context_window` = declared context + one 4,096-token block (GLM 36,864, Bonsai
   and Muse 69,632), added by W12. This clause, and `patch-omlx-mtp.mjs`'s own header,
   both still claimed `DESIRED` was empty; it holds three entries and GLM's is
   load-bearing. Every serve check must assert **`finish_reason:
   stop` and non-empty `content`, with `max_tokens` at 4096 or above** — sharpened by
   W1, which found that a short cap returns the whole reasoning inline in `content`
   with no `reasoning_content` key, so a bare non-empty test passes a dead answer;
   and raised from 1024 to **4096 by W6**, which passed the gate on a trivial prompt
   and then failed it three times on a real coding prompt, because Bonsai spends
   ~1300 reasoning tokens before answering. **W14 raises the working figure again, to
   8192**: 4096 is the floor, but `opencode.json` gives every declared model
   `output: 8192`, so measuring at 4096 under-provisions against production by half and
   manufactures failures — it made GLM hit the cap mid-module. Measure at what the
   models actually get. **W14 also finds oMLX does not honour `do_sample`**: all three
   models sampled, including Muse, whose `generation_config.json` sets it false, and
   Bonsai, which ships no such file. Never infer determinism from a config — probe it.
10. The `lmstudio` provider block in `opencode.json` **stays**, rewritten to declare
    all three models, so the same model can be A/B'd across both runtimes. **W10 breaks
    this for Muse Glimmer** — LM Studio's MLX runtime cannot load it, and W10 deleted the
    GGUF that was its only other route, so that model is **oMLX-only** and the block
    declares fewer than three. W10 also proved LM Studio **indexes models it cannot
    run**, so the two remaining rows need a real load test:
    [Verify which roster models actually load in LM Studio](tickets/16-lmstudio-load-check.md)
    settles which survive, and W9 waits on it. **W16 settles it, and the block declares
    one model cleanly, not two.** Both remaining models load — Bonsai in 8.77 s / 7.94 GiB
    and GLM in 16.27 s / 22.68 GiB — but only **Bonsai answers the gate**. GLM runs to
    `finish_reason: length` on every bare turn, because LM Studio honours only the single
    `eos_token` from `tokenizer_config.json` and ignores the other two ids `config.json`
    declares; GLM ends its turns with `<|user|>`, so nothing stops it. Supplying
    `stop: ["<|user|>", "<|observation|>"]` returns `finish_reason: stop` in 14 s, so GLM
    is declarable **only with those stop strings carried in its config**. **W9 closes the
    constraint: the block declares both models, and both answer through opencode.** A
    model's `options` object is spread verbatim into the request body, so the stop list
    reaches LM Studio and GLM stops. W9 adds two facts the constraint did not hold: the
    block also needs a **`whitelist`**, because `lmstudio` is a built-in models.dev
    provider whose three phantom models a `models` block extends rather than replaces; and
    **`limit.context` never reaches LM Studio**, which fixes context at load time, so the
    A/B needs `lms load --context-length` to match the declared budget.
11. ~~Disk is **99% full (14 GiB free)**~~ — **resolved on its own during W5.** Free
    space rose from 11.5 GB to **46–57 GB (95% full)** with no action taken, exactly
    as W4 predicted: macOS released the APFS Time Machine local snapshots that pinned
    the space. The KV-cache budget stays at **25 GB** (measured working, and the SSD
    tier now indexes real blocks — 320 files, 4.13 GB). Disk is no longer a
    constraint on this map. **W6 qualifies that**: one Bonsai measurement session took
    the cache from 5.15 GB to **24 GB** — right at the proposed cap — and free disk
    from 46 GB back down to **23 GB**. A model switch orphans the lot: the server
    logged `skipped_incompatible=399 blocks (5.15 GB)`, GLM's whole cache, unusable
    under Bonsai. So 25 GB is workable but not generous, `_prune_cache` is load-bearing
    rather than a safety net, and W7 should expect to start from a full cache. **W7 did**
    — it pruned 23.94 GB down to 4.83 GB before measuring — and then **wrote nothing to
    the SSD tier at all**, because Muse Glimmer's 13 KB/token KV never fills the 8 GB hot
    tier. The disk budget is therefore sized by Bonsai and GLM alone. **W10 returns 16.9
    GiB** by deleting the Muse Glimmer GGUF, but `df` does not show it yet: eleven APFS
    Time Machine local snapshots hold the space, so it is purgeable rather than free —
    the same behaviour W4 found. Free disk reads 47 GiB, 95% full, unchanged across the
    delete.

**Model facts already established** (read from configs on disk, so no ticket needs
to re-derive them):

- **GLM 4.7 Flash** — `glm4_moe_lite`, 47 layers, hidden 2048, **64 routed experts,
  4 active + 1 shared**, MLA (`kv_lora_rank` 512 + `qk_rope_head_dim` 64) ⇒ ~54
  KB/token, ~3.5 GB at 65k. Native window 202,752. `num_nextn_predict_layers: 1`
  — an MTP head is present.
- **Bonsai 27B** — `qwen3_5`, a **VLM** with `language_model_only: False`, so the
  vision tower loads either way (it costs ~0.90 GB; W6). Text side: 64 layers, 4 KV
  heads, head_dim 256, `layer_types` runs 3 linear : 1 full ⇒ only **16 layers cache
  KV**. **W6 corrects the KV figure**: oMLX does not honour the card's 4-bit KV claim
  (`turboquant_kv_bits=None`), so KV is fp16 at **64 KB/token**, ~4.0 GB at 65k, not
  the ~1 GB the card implies. Native window 262,144. Its `mtp_num_hidden_layers: 1`
  is empty — 0 of 2180 tensors carry an MTP head, as with GLM.
- **Muse Glimmer** — 30B VLM with a perception encoder (~3.63 GB of the 18.99 GB).
  **W7 corrects the attention shape**: `layer_types` runs 3 `sliding_attention` : 1
  `full_attention` at `sliding_window: 2048`, so only **13 of 52 layers** cache KV
  ⇒ **13 KB/token** plus a fixed ~0.16 GB rotating term, ~**1.0 GB at 65 k** — not the
  ~52 KB/token an all-layers count implies. 2 KV heads, head_dim 128. Native window
  **131,072**, the shortest of the three. Only 13 layers see the whole window, so
  long-range recall is structurally weaker than 52 layers suggests.

**The open risk landed, and the roster absorbed it.** Muse Glimmer was the same 30B
removed on 2026-08-10 for prefill of ~200 tok/s, and the map treated the mlx-community
build as unmeasured rather than known-bad. **W7 measured it: 64.5 s at 187–200 tok/s.**
The flat 4-bit quant did not fix prefill. **W13 keeps all three models anyway**, on two
grounds: the cold prefill is a *door charge* paid once per directory visit, not a
per-turn tax (measured), and no measurement on this map tests **capability**, so
dropping a model on speed alone would rest on a quality claim nobody has.

**The roster rested on speed and memory. W14 measured capability, and it inverts the
order.** Four multi-turn tasks, graded by executing each model's own output, 3 repeats
each: **Muse Glimmer 9/12 pass@1, GLM 6/12, Bonsai 5/12** — so the fastest model is the
weakest coder and the slowest is the strongest. Two results matter more than the ranking:
**GLM never once recovered from a repair turn** carrying real failure output (0 of 12,
against Bonsai's 3 and Muse's 2), and **GLM wasted 4 of 12 turns** by running to
`finish_reason: length` without answering. Both bite hardest in this repo's own agent
loop, where `post-edit-check` throws errors back at the model. The measurement covers
**short prompts only** (every one under 4,000 tokens) and says nothing about long-context
work. It does not redraw the roster — and **W18 has now redrawn the default with it**.

**W18 supplies the metric the map was missing.** Every speed number here is priced *per
token*, which flatters a model that fails, because a wasted turn is fast. Dividing each
model's own recorded wall by the tasks it solved inverts the ranking: **Muse 3.46
min/solved, GLM 3.83, Bonsai 4.09** — so the slowest decoder is also the cheapest per
outcome, and GLM's speed advantage does not survive its 79% wasted wall-clock. Computed
from W14's stored results, not re-measured. It holds at ~1.5k-token prompts and says
nothing about a 12–25k agentic context, where GLM's prefill lead is larger.

**W21 went to that agentic context, and the ranking dissolves there.** At ~17.6k the
pass@1 spread **9 / 6 / 5 becomes 8 / 6 / 7**; Muse's four-point lead over Bonsai becomes
one, and on pass@≤2 they **tie at 8/9**. Every gap now sits inside the noise band. The
default held on W21's pre-registered floor — a challenger needed +3 and Bonsai only drew
level — **not on the evidence**, which no longer separates the three. W23 then moved it to
Bonsai on 2026-08-14 regardless, on footprint and cost per solved task. Two corrections ride
with it, and both reach past this ticket: **every decode rate in the roster table is a
short-context number** (26 / 68 / 38 tok/s become ~11 / 23 / 12.5 at 17–22k, all three
losing about two-thirds, with GLM keeping its relative 2× lead), and **`cached_tokens`
rounds to 2048 only on some models** — GLM matches at **256**, so W13's rule, measured on
Bonsai and generalised, understates GLM's cache eightfold. The retrieval worry that made
the ticket urgent is **dead**: a six-needle probe at ~22k returned **36 of 36**, and Muse
read a needle 21,000 tokens back as reliably as one 1,050 tokens back.

**Door charge vs per-turn prefill** (W13, measured on Bonsai, `max_tokens: 1`): a cold
12.8k visit costs 58.6 s, then each turn prefills only its fresh tokens at the model's
ordinary rate — 5.5 s for a small tool result, ~23 s for a 2k one. `cached_tokens`
rounds **down to a 2048-token block**, so up to ~2k tokens of already-seen prefix are
re-prefilled every turn. The vocabulary is fixed in [CONTEXT.md](../../CONTEXT.md);
method and scripts are in
[assets/w13-prefix-extension](assets/w13-prefix-extension/).

## Decisions so far

<!-- one line per closed ticket -->

- [Prove weight sharing between LM Studio and oMLX](tickets/01-prove-weight-sharing.md)
  — Sharing works today, on the pinned oMLX, with no upgrade. `~/.omlx/models/<org>/<repo>`
  symlinks to `~/.cache/huggingface/hub/<org>/<repo>`; one inode serves both tools and
  `lms ls` is unchanged. The served id is the directory **leaf**. oMLX also scans the
  HF cache by itself (`hf_cache_enabled`), so the symlink wins the tie-break rather
  than granting visibility.
- [Confirm the oMLX upgrade target and its architecture support](tickets/02-confirm-upgrade-target.md)
  — Upgrade to tag **`v0.5.8.dev3`** (`350dc08b`), not the tip, which only adds a
  web-search dependency. It needs **no compiler**: custom kernels are opt-in behind
  `OMLX_WITH_CUSTOM_KERNEL`. All six `omlx serve` flags survive, the KV cache format
  stays at `"3"` so the existing blocks live, and leaf-keyed `model_settings.json`
  still holds. Muse Glimmer is the only model the upgrade buys — oMLX **vendors** its
  mlx-vlm implementation, so mlx-vlm never has to reach 0.6.12, and vendoring by hand
  would break quantized logits. Rollback is partial unless `mlx` and `transformers`
  are pinned explicitly, because the old pyproject uses floors.
- [Get Muse Glimmer 30B 4-bit MLX into the LM Studio store](tickets/03-acquire-muse-glimmer.md)
  — Present and complete: 19.41 GB, 4 shards matching the index exactly, flat 4-bit
  affine (not mxfp4), at `~/.cache/huggingface/hub/mlx-community/Muse-Glimmer-30B-4bit`.
  `lms ls` lists it as an LLM, but 815 of its 2278 tensors are vision. KV is cheap
  (~52 KB/token, ~3.4 GB at 65 k). No oMLX symlink yet; W8 owns that.
- [Serve-check GLM 4.7 Flash 6-bit and measure it](tickets/05-serve-check-glm.md) —
  **Serves correctly, but 65,536 context is unreachable.** The gate passes at its
  defaults (no settings pin), tool calling parses, decode is ~68 tok/s, cold prefill
  ~590 tok/s and a warm prefix restores in ~1 s. The blocker is oMLX, not the model:
  it sizes this model's MLA KV with the MHA formula and charges **362 KB/token against
  a real 52.9**, so the prefill guard rejects 65k in 5.1 s with the model alone in
  memory. 20k answers; 45k is rejected after 145 s. Raising the guard fails (the Metal
  cap binds), TurboQuant is barred for MLA, and no per-model KV override exists. The
  cap is now [Decide GLM's context cap against oMLX's 7x MLA over-count](tickets/12-glm-context-cap.md).
- [Serve-check Ternary Bonsai 27B 2-bit and measure it](tickets/06-serve-check-bonsai.md)
  — **Passes every functional check and fails on latency.** Serves at its defaults,
  splits reasoning, calls tools in 3.11 s, loads the ternary quant, costs only
  **8.44 GB** resident, and **reaches 65,536 context** with zero warnings — but
  prefills at **194 tok/s**, so a 12,818-token turn waits **66.2 s** for its first
  token, matching the ~64 s that removed `--muse`. Decode ~38 tok/s; a warm 25k prefix
  restores in ~3.5 s. The KV over-count does **not** reach this model: oMLX prints a
  4×-inflated block estimate but the admission path uses the correct 16-of-64 layer
  count, so GLM's fault stays narrow. The unbuilt Metal kernels cannot help — they are
  decode-only, and the prefill kernel already runs. Roster decision raised as
  [Decide the roster now that Bonsai prefills at ~200 tok/s](tickets/13-roster-after-prefill.md).
- [Upgrade the oMLX stack in place](tickets/04-upgrade-omlx-stack.md) — **Done.**
  `omlx 0.5.8.dev3` at tag `v0.5.8.dev3` (`350dc08b`), with `mlx 0.32.0`,
  `mlx-lm ab1806e8`, `mlx-vlm 0.6.3` (`78b96eb5`) and `transformers 5.12.1` — every
  version W2 predicted. Nothing compiled, no flag changed, and `/v1/models` answers
  HTTP 200 listing all three models plus `bge-m3`. Muse Glimmer's registration and its
  vendored compat patch are both present. Rollback is one checkout plus one install
  with three explicit pins; the exact before-state is in the ticket.
- [Serve-check Muse Glimmer 30B 4-bit and measure it](tickets/07-serve-check-muse.md)
  — **Works, and repeats history: 64.5 s to first token on a 12,882-token prompt**
  (187–200 tok/s), against the ~64 s that removed the oQ4e build on 2026-08-10. Passes
  every functional check at its defaults — `finish_reason: stop`, reasoning split,
  tool call in 5.28 s, no logit collapse — and reaches 65,536 context with no warning
  of any kind, in 6 m 54 s. But it decodes slowest on the roster (**26 tok/s**) and
  costs **18.59 GB**, so **Bonsai beats it on every axis**. The KV over-count does not
  reach it: the model is 3 sliding : 1 full attention, so only **13 of 52 layers** cache
  KV ⇒ ~13 KB/token, **~1.0 GB at 65 k** — the cheapest KV of the three, and it writes
  nothing to the SSD tier.
- [Decide the roster now that Bonsai prefills at ~200 tok/s](tickets/13-roster-after-prefill.md)
  — **All three stay; the destination table is unchanged.** GLM keeps the current 6-bit
  build, `--bonsai` and `--muse` both declare 65,536, GLM's cap stays with W12. Two
  findings drove it: the ~60 s is a **door charge per directory visit**, not a per-turn
  tax (turn 2 re-uses 12,288 cached tokens; later turns cost 5–25 s), and the "Muse is
  dominated" claim covered **only speed and memory** — no measurement on this map tests
  capability, so it could not carry a drop. TTFT gates the **default** only. Scope line:
  a new model is out, a re-quant of a roster model is in.
  `unsloth/GLM-4.7-Flash-NVFP4` **cannot load** — compressed-tensors `mixed-precision`,
  which mlx-lm mis-declares as int4-affine-g32 and oMLX only corrects for `laguna`.
- [Rewrite ai.sh — profiles, _ensure_model, disk budget, patch scripts](tickets/08-rewrite-ai-sh.md)
  — **Done, and all three profiles launch, link, serve and answer.** `_ensure_model` is
  now a verifier: no `hf download` path at all, and it fails by repo id when weights are
  absent, when LM Studio is still fetching them, or when a real directory sits where the
  symlink belongs. It created the Muse Glimmer link W3 left open, and a new
  `_prune_stale_model_links` cleared the five departed links. Old flags exit 1 naming the
  roster. **`hf_cache_enabled` stays true** — pinning it false cannot deliver "three and
  no others" anyway, because `MarkItDown` rides in on a dependency, and the `--model-dir`
  tie-break already makes the roster exact. **The state file's line 2 now records
  `<binary>@<git HEAD>`**, the only cheap signal that survives an in-place upgrade.
  `DESIRED` in `patch-omlx-mtp.mjs` is empty: no roster model needs a pin. Disk budget
  cut to 25 GB, and `opencode-mem.jsonc`'s summarizer fallback repointed off a model
  that no longer exists.
- [Remove the Muse Glimmer GGUF](tickets/10-remove-muse-gguf.md) — **Deleted, 18.16 GB
  (16.9 GiB), with the user's confirmation — but the precondition failed and the premise
  inverted.** The GGUF went because it ran **nowhere**, not because one MLX copy now
  serves both tools: `lms load muse-glimmer-30b` **fails**, since LM Studio's MLX runtime
  carries mlx_vlm **0.6.5** with no `muse_glimmer` module, upstream needs 0.6.12, and
  oMLX serves the model only by **vendoring** it. `lms runtime update` closes nothing.
  So **Muse Glimmer is oMLX-only** and weight sharing is one-directional for it. LM
  Studio *indexed* the copy perfectly and still could not run it — **indexing does not
  predict loading** — which is why GLM and Bonsai now need
  [Verify which roster models actually load in LM Studio](tickets/16-lmstudio-load-check.md)
  before W9 declares them. `lms ls` is byte-identical across the delete (5 models,
  52.47 GB), proving the GGUF was already an orphan; `~/.lmstudio/models/` is now empty.
- [Measure coding capability across the three profiles](tickets/14-capability-comparison.md)
  — **Muse Glimmer writes the best code: 9/12 pass@1 against GLM's 6/12 and Bonsai's
  5/12**, so the capability order is the reverse of the speed order. Four multi-turn
  tasks — a tool chain with a planted decoy, a both-key-spellings idempotent merge, a
  Bash cache-prune repair, and an extend-without-regressing revision — 3 repeats each,
  every one graded by **executing** the model's output. Two findings outweigh the
  ranking: **GLM never recovered from a repair turn** (0/12, against Bonsai 3 and Muse 2)
  and **wasted 4 of 12 turns** running to `finish_reason: length`; both hurt most in this
  repo's `post-edit-check` loop. **T3 is 0/9 first-shot** — every model corrected the
  quoting and ordering yet left a real defect (GLM kept `for f in $(ls)`; the others
  reached for GNU `find -printf`, absent on macOS), a blind spot in the language `ai.sh`
  is written in. Bonsai's 2-bit quant shows no collapse. Method, limits and the T3
  re-grade: [assets/w14-capability](assets/w14-capability/).
- [Decide GLM's context cap against oMLX's 7x MLA over-count](tickets/12-glm-context-cap.md)
  — **GLM declares 32,768, with a 36,864 safety rail. Option C was taken, works, and
  does not deliver 65,536.** The over-count is corrected (~374 → 52.9 KB/token, 7.08×;
  KV at 65 k drops 23.41 GB → 3.30 GB) by a new idempotent `patch-omlx-mla-kv.mjs`.
  **The ticket's stated root cause was one level off**: the `.caches` loop it named is
  unreachable, because `glm4_moe_lite` defines no `make_cache`, so the estimator bails
  at `cache_list is None` first — a patch to the loop alone changed nothing and was
  reverted. **The binding constraint was never KV.** With KV honest, the guard *admits*
  45,072 tokens and the prefill then force-stops against the physical Metal cap and
  unloads the model, because the peak is the activation transient — which the guard
  now **under**-prices (`KV+SDPA 1.55 GB` quoted against >14 GB real). So C removed a
  safety net, and the pinned `max_context_window` puts it back: 45,072 → clean 400 in
  1.67 s. Rail ≠ budget deliberately — mirroring them hard-rejected a 32,784-token
  prompt built for 32,768. Method and the three discarded runs:
  [assets/w12-mla-kv-cap](assets/w12-mla-kv-cap/).
- [Try the DFlash drafter on Muse Glimmer](tickets/15-dflash-drafter-muse.md) — **The
  drafter engages and makes the model worse on every axis; DFlash stays off.** Decode
  **−15 %** (26.9 → 22.8 tok/s), cold prefill **+21 %** (194 → 161 tok/s), peak RSS +3.9 GB,
  and two concurrent requests **serialize** (2.4× a single, against the baseline's 1.33×),
  because DFlashEngine bypasses the scheduler. Engagement is proved from the log, not the
  rate. **The finding that outranks the decode number: DFlash's prefix cache made 9 lookups
  and 0 insertions**, so an identical repeated 12,189-token prompt re-prefilled from scratch
  (`cached=0`, 77–87 s against the baseline's 10.6 s) — confirmed after a real generation,
  not an artefact of `max_tokens: 1`. That **inverts W13's door charge for this path**: every
  turn re-pays the full prefill. The drafter costs **1.34 GB** quantized (4.76 GB if not —
  the `w4` registry default never reaches oMLX and must be asked for), and needs no symlink,
  because oMLX finds it in the HF cache and classes it a helper hidden from `/v1/models`.
  Method: [assets/w15-dflash](assets/w15-dflash/).
- [Verify which roster models actually load in LM Studio](tickets/16-lmstudio-load-check.md)
  — **The `lmstudio` block declares one model honestly, not two — and the app was gone
  from the box.** Only the CLI, runtimes and data survived a failed self-update, so the
  ticket reinstalled LM Studio (0.4.21+2) with the user's approval. Both remaining models
  then **load**: Bonsai 8.77 s / 7.94 GiB, GLM 16.27 s / 22.68 GiB. Only **Bonsai answers
  the gate**. GLM answers correctly and then never stops — it emits `<|user|>` and
  fabricates a dialogue to the 8192-token cap, because LM Studio honours only the single
  `eos_token` in `tokenizer_config.json` and ignores the other two ids in `config.json`
  (`<|user|>` 154827, `<|observation|>` 154829). **The fault is the runtime, not the
  model**: one added `stop` list turns 8191 tokens in 291.89 s into 509 tokens in 14.02 s,
  and oMLX passed these same weights in W5. Keys for W9: `zai-org/glm-4.7-flash` and
  `prism-ml/bonsai-27b`. **The reinstall changed no runtime** — still `mlx_vlm 0.6.5` — so
  W10's Muse verdict stands untouched. Two incidental findings: LM Studio's own
  `model-data.json` had already recorded both successful loads and Muse's failure, and the
  fresh app **ignores its own `downloadsFolder`**, needing symlinks into
  `~/.lmstudio/models` to see anything.
  Method: [assets/w16-lmstudio-load](assets/w16-lmstudio-load/).
- [Rewrite opencode.json — both the mlx and lmstudio providers](tickets/09-rewrite-opencode-json.md)
  — **Done: `mlx` declares the three, `lmstudio` declares two, and both halves are proved
  end to end.** GLM 32,768 (W12), Bonsai and Muse 65,536 (W13), every row
  `"temperature": false`. GLM's LM Studio row carries `options.stop`, and a stub server
  recording the wire body proves the key is spread verbatim into the request — a general
  lever, since **any body parameter the endpoint understands can be declared per model**.
  A paired control on one load settles it: no stop → `finish_reason: length` and the
  fabricated `<|user|>thought:` dialogue; with stop → `stop`, 115 tokens. Through opencode,
  GLM answered in 35.0 s and Bonsai in 53.3 s. **The ticket missed one lever: `lmstudio` is
  a built-in models.dev provider**, so a `models` block *extends* its roster instead of
  replacing it and the picker listed three phantom models this box does not hold;
  `whitelist` cuts it to the declared pair. **And `limit.context` never reaches LM Studio**
  — it fixes context at load time, so a bare `lms load` failed every turn until
  `--context-length 32768`. Method: [assets/w9-opencode-json](assets/w9-opencode-json/).
- [Decide the default profile now that capability is measured](tickets/18-default-after-capability.md)
  — **Muse Glimmer takes bare `ai`; GLM moves to `--glm`. Made, validated, in the tree.**
  The decision turns on a metric no prior ticket computed: **minutes per solved task**,
  each model's own wall divided by what it actually solved — **Muse 3.46, GLM 3.83, Bonsai
  4.09**. Muse decodes 2.6× slower per token and is *still* cheapest per outcome, because
  GLM spent **18.2 of 23.0 minutes producing nothing** against Muse's 5.3 of 38.1. Two of
  the ticket's stated costs vanished on inspection: Muse is **lighter** than GLM (18.59 vs
  22.67 GB) and declares **65,536** against GLM's 32,768, so the swap frees ~4 GB and
  doubles the default's window. The price is real and one-sided — decode never amortises,
  so every answer is 2.6× slower per token, and the door charge rises 21.8 s → 64.5 s.
  **A latent trap was caught in the act**: `ai.sh` tracked the profile as the string
  `"default"` and the GLM MLA fail-safe keyed on it, so a one-line swap would have capped
  the *new* default at 24,576 while leaving GLM uncapped. GLM's challenge is registered
  **before** it runs, at ≥9/12 solved then lowest min/solved:
  [Measure GLM with thinking pinned off](tickets/19-glm-thinking-pin.md).
- [Measure GLM with thinking pinned off](tickets/19-glm-thinking-pin.md) — **The pin works
  perfectly and loses anyway. It is off; Muse Glimmer keeps the default.** Every runaway
  gone (4/12 → **0/12**), reasoning 151,688 chars → **0**, wall **23.0 → 1.9 min** on a
  twelfth of the tokens — and solved fell **6/12 → 4/12** against a floor of 9. The
  reasoning is load-bearing: the control's two T2 passes cost 9,431 and 26,413 reasoning
  chars, and pinned GLM instead imported packages that do not exist (`lodash-es`,
  `deepmerge` — zero times in the control) and emitted Bash failing `bash -n`. **The cure
  converts wasted turns into wrong answers, not right ones** — T3 went `P P F` → `F F F`,
  three failures either way. **This run is the argument for having a capability floor**:
  at **0.47 min/solved** the pinned GLM scores 7× better than Muse on W18's own deciding
  metric while solving a third as many tasks, because a model that fails fast is cheap per
  outcome. Two limits kept: 6 → 4 sits **inside** this suite's declared noise band, so the
  honest claim is no measured gain rather than proven harm (the floor decision is safe at a
  gap of five); and the pin-off probe showed runaways report `reasoning_content` **empty**,
  because oMLX splits only at the closing tag. A revert trap was caught: `patch-omlx-mtp.mjs`
  **never deletes a key**, so emptying `DESIRED` leaves the live pin in force — it had to be
  removed from `model_settings.json` by hand.
  Method: [assets/w19-thinking-pin](assets/w19-thinking-pin/).
- [Buy prefill headroom for GLM — Metal cap, hot-cache size and the 4-bit re-quant](tickets/17-glm-prefill-headroom.md)
  — **No lever taken, and the question dissolves: memory is not what binds.** The user
  waits at most **120 s** for a cold open, prefill grows as O(n²), so **time** caps the
  context long before the Metal cap does. W12's ladder already brackets that limit with
  measured points — 32,783 at **116 s**, 40,976 at **266 s** — so no new measurement was
  owed. Fitting the two rungs *below* the throttle predicts 32,783 at 123 s (measured
  116, **0.94×** — natural rate) and 40,976 at 182 s (measured 266, **1.46×** — throttle),
  which locates the throttle **between** them: below the declared cap there is no
  throttle for a memory lever to remove. Solved for 120 s the fit gives **~32,311
  tokens**, so W12's memory-chosen 32,768 lands within **1.5 %** of the time boundary by
  accident. Two of the ticket's premises were wrong: **`--memory-guard-gb` never set the
  abort limit** (that is `min(static, metal) − hot_reservation`; static 62 GiB, metal
  **51.84 GiB**), and **lever B cannot buy cold headroom at all**, because the hot-cache
  reservation tracks *use* not the cap — it was 1.5 GiB during the ladder, and
  51.84 − 1.5 = 50.3 is exactly the abort in W12's log. **Lever A was approved
  mid-grilling and then re-opened and declined**, when peak RSS on every passing rung
  read 23–28 GB against a 51.84 GiB cap: it was insurance against a case nothing on this
  roster reaches, and it switches on `mx.set_wired_limit`, whose failure mode (#2184)
  needs a reboot. Lever C was verified before it was declined (16.87 GB, same
  `glm4_moe_lite`, same MLA fields, same three eos ids — a clean drop-in). **No profile
  opens a 45,000-token file in two minutes**: GLM reaches ~32,300 tokens in 120 s and
  Muse ~22,800, so switching profile is not a workaround and `--glm` is already the right
  one. The under-priced peak is **reported, not patched**, with the report written and
  unfiled. Method: [assets/w17-prefill-headroom](assets/w17-prefill-headroom/).
- [Rewrite CLAUDE.md and ai.env.example for the new roster](tickets/11-rewrite-claude-md.md)
  — **Done: `CLAUDE.md` and `AGENTS.md` rewritten, `ai.env.example` corrected additively,
  every validation command passing — and the ticket's own premise disproved.** "The roster
  pins nothing" is false: `DESIRED` holds three `max_context_window` rails from W12, and
  the script's own header still called itself empty, so the docs now separate **no pinned
  behaviour** from **one pinned rail per model**. The never-deletes trap is documented
  against a live instance, not a principle — `model_settings.json` still carries inert
  Qwen-oQ6 and Gemma entries. **Three source comments contradicted their code and were
  fixed** (comment-only): `ai.sh` claimed GLM's rail "still reads 65,536" when it reads
  36,864, `ai.sh` named retired flags `-l`/`-m` in the advisor block, and the patch header
  above. **`ai.env.example` was not finished by W8**: four variables that `ai.sh`, its
  patches or the lint plugin actually read were undocumented (`OMLX_BASE_DIR`,
  `SMART_CODING_OMLX_DIR`, `OPENCODE_MEM_MAX_CONTEXT_CHARS`, `OPENCODE_LINT_*`), and
  `HF_HUB_CACHE` also honours `HF_HOME`. `AGENTS.md` additionally claimed a `skills/`
  directory holding 22 skills, which does not exist. Capability is cited, not caveated
  away — W14's numbers and W18's metric, with both stated limits kept. One live fact
  flagged and deliberately untouched: `opencode.json`'s top-level `model` is an
  **uncommitted** change to `zai/glm-5.2` with no `zai` credential in `auth.json`, so a
  bare `opencode` needs a login; it reaches no profile, since `-m mlx/<id>` wins.

- [Decide the summarizer model now the default decodes at 26 tok/s](tickets/20-summarizer-model.md)
  — **Option A, the session's own model — and the arrangement does not change. What
  changes is the plugin's abort, because auto-capture on the default was not costly
  but broken.** Every capture on Muse exceeds the 30 s per-iteration abort, so **0 of
  8** completed and nothing was ever saved. **The abort is decode-bound, which kills
  the obvious cure**: shrinking the input cap cuts prefill exactly as expected (7,494
  → 1,260 prompt tokens) and the wall *rises*, because Muse reasons more with less
  context — **44 s at 24,000 chars against 76 s at 2,000**. Option C dies with it,
  since iterations cannot rescue a timeout iteration 1 already blows. **Sharing one
  model is cheaper than adding a small second one**, the reverse of the ticket's
  assumption: Bonsai retains 72–74 % of the next turn's decode against same-model
  Muse's 77–81 %, because two models run two forward passes instead of one batched
  pass — the ticket's memory arithmetic was sound (33 GB, no eviction), it was the
  decode cost nobody had priced. GLM fails harder, at **44 GB** against the 40.8 GB
  soft target, reproducing the documented ping-pong. Fixed by three settings as one
  package: `autoCaptureIterationTimeout` 30 s → **180 s**, `autoCaptureMaxIterations`
  8 → **2**, and `memoryExtraParams {"max_tokens": 2048}` to close a **32,768**-token
  runaway the provider left open by sending no `max_tokens` at all — a supported
  config lever, so no fourth patch. Verified at 38.7 / 44.6 / 49.6 s, all three
  returning a parsed `save_memory` call. **`ps` RSS under-reads MLX by 1.66×** (18.64
  vs 31 GB real), putting a number on W17's caveat.
  Method: [assets/w20-summarizer](assets/w20-summarizer/).

- [Measure capability at the largest context all three profiles share](tickets/21-long-context-capability.md)
  — **W14's ranking does not survive at a long prompt, and neither does any other. Muse
  Glimmer keeps bare `ai` on the floor, not on the evidence.** Two stages, both against a
  floor fixed in writing first. **Stage 1 kills the worry that made the ticket urgent**: a
  six-needle retrieval probe at ~22k returned **36 of 36**, every answer exact, with Muse
  reading a needle **21,000 tokens back** as reliably as one 1,050 tokens back — 13
  full-attention layers are enough, and the probe saturated so it ranks nothing. **Stage 2
  dissolves the ranking**: on the trimmed T1/T2/T4 suite at ~17.6k, pass@1 goes **9/6/5 →
  8/6/7**, pass@≤2 **9/6/8 → 8/7/8**, so Muse and Bonsai tie and every gap sits inside the
  noise band. **Bonsai is cheapest per solved task there (2.31) and degrades least
  (1.12×); GLM degrades most (1.73×)** — the reverse of its prefill lead, because prefill is
  paid once and decode per token. Neither floor rule fired, so the default stood at the time —
  **and [W23](tickets/23-default-to-bonsai.md) moved it to Bonsai the next day anyway**, on
  footprint and cost per solved task, with the unmet floor recorded rather than argued away. Three
  traps: **the ticket's cost premise was wrong** (a constant head is prefilled once — 130.4
  → 26.0 s on Muse), **its ~28,000-token target overshoots GLM's real budget** (28,000 +
  8,192 > 32,768; the honest ceiling is 24,576, and 28,000 fits only the rail), and
  **Stage 1's corpus cannot be re-used** because it contains T2's and T4's actual answers —
  Stage 2's builder asserts none survive. One contaminated run was found and repaired: the
  Mac slept **75.1 min** (`Clamshell Sleep`) mid-GLM, inflating one run to 5,057 s; verdicts
  held, wall repaired 100.6 → 25.5 min from `pmset` windows. Caps do not converge.
  Method: [assets/w21-long-context](assets/w21-long-context/).

- [Repair Muse Glimmer's tool calls in opencode](tickets/22-muse-toolcall-corruption.md)
  — **The model makes a small recurring slip; oMLX's parser turns it into a dead turn, twice
  over. Fixed in the parser, because the slip is not fixable here.** Muse frames a tool call
  as a header naming the tool plus an XML body naming it **again**, and sometimes carries the
  header's `<name><|message|>` pattern into the tag: `<atem:invoke name="bash<|message|>">`.
  Then `_INVOKE_RE` captures `name="([^"]+)"` — anything but a quote — so the special token
  becomes the tool name and opencode rejects the call; **and the adapter already had the right
  name**, since the header's `to=bash` parsed correctly via `[^\s<]+`. Meanwhile
  `_MuseChannelSplitter` honours that stray `<|message|>` even while the channel is already
  `"tool"`, so the open tool body is re-classified as text and the rest of the XML streams to
  the user. Ground truth came from opencode's own SQLite, and `parser-repro.py` reproduces
  both halves **byte-for-byte** against oMLX's adapter in 0.06 s, with no server and no model.
  Fixed by `patch-omlx-muse-toolcall.mjs` (name truncated at the first `<`; `<|message|>`
  ignored inside a tool body), `+musetc` on the build string. **Truncating rather than
  tightening the regex is deliberate** — `[^"<]+` would make the tag fail to match and drop
  the call, which is worse than mis-naming it. Three findings ride along: the launcher's warn
  is keyed on the **model**, not the profile, because Muse serves both bare `ai` and `--muse`
  and the flag test would leave the default unguarded — **W18's trap, live again**; the defect
  **never reproduced live** across one tool, sixteen tools, streaming and four parallel calls,
  so its frequency is unmeasured; and **nothing on this map would have caught it**, because a
  serve check that proves a model runs does not prove its tool calls survive an agent turn.
  Method: [assets/w22-muse-toolcall](assets/w22-muse-toolcall/).

- [Move the default profile to Ternary Bonsai](tickets/23-default-to-bonsai.md) — **The
  default moves to Bonsai on 2026-08-14, by the user's decision, and the ticket says plainly
  that W18's floor is not met.** W21 had already dissolved the capability argument at agentic
  length — 7 / 8 / 6 on pass@1, Muse and Bonsai tied at 8/9 on pass@≤2, every gap inside the
  noise band — and left Bonsai cheapest per solved task (2.31 against 3.19 and 3.64), least
  degraded by length (1.12×) and **less than half the resident footprint** (8.44 GB against
  18.59). What the move gives up is Muse's short-prompt lead, 9/12 against 5/12, the largest
  measured capability gap on this roster; it is one flag away at `--muse`. **No fail-safe
  needed an edit**, which vindicates two earlier choices: the GLM context guard keys on the
  profile **name** rather than a `"default"` sentinel (W18), and the Muse tool-call warning
  keys on the **model id** rather than the flag (W22). Three consequences carried: the
  default now **fills the KV cache** (fp16 KV at ~64 KB/token against Muse's ~13), it has the
  **tightest patience boundary** of the three (~21,000 tokens in 120 s, interpolated), and
  **no summarizer capture has been timed on it** — W20's settings stay as measured on Muse.

## Not yet specified

- **The two custom Metal kernels the upgrade ships but does not build.** Much narrower
  after W6, which supplied the kernel-free baseline. `omlx.custom_kernels.bonsai` is a
  **decode-only** kernel (quantized matrix-*vector* qmv, plus a speculative-decode
  verify) and `has_native()` is `False` here, so building it under
  `OMLX_WITH_CUSTOM_KERNEL=1` would lift Bonsai's ~38 tok/s decode and **cannot touch
  its 194 tok/s prefill**. The prefill kernel needs no building at all — the
  `qwen35_gdn_chunked` patch already runs `impl=blocked_seq`, its own fastest route.
  So this is now a decode-tuning option — and **W13 keeps Bonsai**, so it has a target
  again: lifting ~38 tok/s is the cheapest remaining win on that profile, since its
  prefill cannot be touched. ~~`glm_moe_dsa._ext` is untouched and still unexamined.~~
  **W17 examines it and closes the GLM half**: the package binds to
  `model_type == "glm_moe_dsa"` (GLM-5.2, DeepSeek sparse attention), and this roster's
  GLM is **`glm4_moe_lite`** — a different model type — so the kernel never engages for
  it. Its sources are decode-shaped anyway (`dsa_indexer`, `dspark_qmv`, `sparse_mla`).
  **W7 closes this for Muse Glimmer**: `omlx/custom_kernels/` holds
  `bonsai`, `glm_moe_dsa`, `minimax_m3`, `qwen35_prefill`, `common` and `nax` and
  **nothing for `muse_glimmer`** — there is no kernel to build for that model at all. **W15
  closes the last one Muse had**: DFlash was its only differentiator, it engaged, and it lost.
  Muse Glimmer's 26 tok/s is now a fixed property of this box, which is what W18 must price.
  **W18 priced it and took it anyway** — so the *default* profile is the one model on the
  roster with no custom kernel at all, and no remaining lever on its decode rate. That
  raises the value of the Bonsai decode kernel only for the `--bonsai` profile; nothing
  here can speed up bare `ai`.
- ~~**Raising context above 65,536.**~~ **Graduated and inverted by W12.** W5 read the
  gate as oMLX's *estimate*; correcting that estimate exactly did **not** raise the
  ceiling, because the real gate is the prefill activation transient against Apple's
  Metal cap. The question is no longer "above 65,536" but "above 32,768", and it is now
  [Buy prefill headroom for GLM](tickets/17-glm-prefill-headroom.md). **W17 closes it,
  and the gate moves once more — off memory entirely.** Prefill grows as O(n²), so the
  user's 120 s limit for a cold open binds at ~32,311 tokens while peak memory sits
  23–28 GB under a 51.84 GiB cap. There is nothing above 32,768 to buy on this box, by
  any lever, for any profile.
- **oMLX's DFlash prefix cache reads but never writes.** New in W15, and the same shape as
  the entry below: a latent defect this map hit but did not chase. Nine requests produced
  `hits=0 misses=9 insertions=0 prefill_tokens_saved=0`, and a repeated identical 12.2k
  prompt re-prefilled in full **after a real generation**, so it is not a `max_tokens: 1`
  artefact. oMLX *does* wire the writer (`PrefixCacheFlow.for_request` builds a
  `SnapshotService`, `omlx/engine/dflash.py:1134`), so the gate that declines to publish sits
  deeper, in `dflash-mlx`'s own runtime. It is harmless today because **DFlash is off for
  every roster model** — which is exactly why it is not a ticket. It becomes one only if a
  speculative path is ever wanted again, and then the question is whether to chase the gate,
  report it upstream, or accept that DFlash and the two-tier cache are mutually exclusive on
  this build. The **acceptance ratio was never measured** either, for a smaller reason:
  `get_speculation_stats()` is served only from `/admin/api/activity`, which 401s without a
  session cookie, and the only way in is an auth flag in the user's own settings.
- ~~**oMLX under-prices the prefill peak it admits.**~~ **Decided by W17: report it, do
  not patch it.** W17 also found the cause. `_admission_estimate` (`scheduler.py:8833`)
  charges the transient of a **floor-size** chunk (256 tokens) while prefill *starts* at
  `prefill_step_size` (2048) and shrinks only once the throttle engages — so on a cold
  server, where no floor-size sample exists, admission uses the throttled steady state (a
  **lower** bound on the peak) as if it were an upper bound. oMLX's own
  `_prefill_speed_priority` branch already prices the un-throttled regime correctly. Not
  patched, because constraint 5 wants one build upgraded in place, the repo already
  carries one source patch, and the `max_context_window` rail already turns the
  five-minute abort into a 1.67 s HTTP 400. The report is **written and unfiled** at
  [assets/w17-prefill-headroom/upstream-report.md](assets/w17-prefill-headroom/upstream-report.md);
  filing it is the user's call, not further map work.
- **W17's memory-headroom margin, re-read with an honest measure.** New in W20, which
  put a number on the caveat W17 itself wrote: `ps` RSS under-reads MLX by **1.66×**
  (18.64 GB against a real 31 GB `phys_footprint`), because MLX allocates through
  `IOAccelerator` and RSS does not count those pages. W17's ladder sampled **RSS**, so
  its "peak 23–28 GB against a 51.84 GiB cap" may correspond to ~38–46 GB real —
  ~10 % headroom rather than the comfortable margin it reads as. **This does not
  reverse W17**: its primary argument is the O(n²) time fit, which never used a memory
  number, and 32,768 stays either way. What it weakens is one *supporting* clause —
  that lever A (raising the Metal cap) was "insurance against a case nothing on this
  roster reaches". Deliberately not a ticket, for two reasons: nothing turns on it
  today, and the 1.66× was measured with **two models resident**, a different memory
  composition from a single-model prefill, so the ratio should not be assumed to
  transfer. It becomes a ticket only if someone re-opens the context cap — and then
  the work is re-running W12's ladder with `footprint -p` instead of `ps`.
- **Whether any profile should run MCP-free.** `-l` owned that behaviour and `-l` is
  gone. W8 kept the kill-switch and made it flag-independent: the branch now reads
  `if (( mcp_free ))` with `mcp_free=0`, so it is one assignment from live and nothing
  claims it yet.
- **Bash has no guard, and no roster model fixes it.** New in W14: **T3 scored 0/9
  first-shot** across all three models on a real `ai.sh`-shaped defect. Each fixed the
  quoting and the ordering and each left something real — GLM kept `for f in $(ls -rt)`,
  which word-splits on the spaces the contract names; Bonsai and Muse both used GNU
  `find -printf`, which macOS does not have. Only Muse repaired it when shown the
  failure. `post-edit-check` lints JS/TS only, so nothing in this repo catches a Bash
  defect the model introduces — in the one language the launcher is written in. Whether
  to add `shellcheck` to the plugin, or to accept it and review Bash by hand, is not yet
  sharp enough to ticket: it needs a look at what `shellcheck` would actually have caught
  here (it flags `for f in $(ls)` as SC2045, and would **not** have caught the macOS
  `find -printf` portability error). **W11 records the gap rather than closing it** —
  `CLAUDE.md`, `AGENTS.md` and `ai.env.example` all now state plainly that
  `post-edit-check` covers JS/TS only and that Bash must be reviewed by hand. So the fog
  is narrower than it was: the *gap* is documented, and only the *decision* is open.
- **Per-model thinking / reasoning pins.** Only if a serve check proves one broken. W1
  saw GLM and Bonsai both split `reasoning_content` from `content` correctly at their
  defaults, and W6 confirmed it for Bonsai at 4096 output tokens — so no pin is needed
  for correctness. W6 does raise a **cost** question the pins could answer: Bonsai
  spends ~1300 reasoning tokens (5202 chars) on a one-line coding question, roughly 33 s
  of its ~38 tok/s decode. **W7 finds the same on Muse Glimmer** — ~600 tokens (2414
  chars) on the same question, ~22 s of a slower decode — and confirms no pin is needed
  for correctness there either, so the old `reasoning: medium` pin is a cost lever only.
  Not broken, but not free either. **W8 leaves `DESIRED` empty and keeps the script
  wired in**, so this is the landing place if a measurement ever justifies a pin; the
  merge machinery is unit-tested and still writes both key spellings. **The GLM half is
  now closed, not just graduated**: W19 pinned it, measured it, and reverted it — the pin
  removed every runaway and cost 2 solved tasks. Do not re-open GLM's pin without new
  evidence; it is a measured no, not an untried idea.
  What stays as fog is the **Bonsai and Muse** half — both reason at their defaults with
  no correctness fault, so a pin there buys back decode time only, and nothing has priced
  that. It matters more now that the default decodes at 26 tok/s. **W19 also raises the
  expected price sharply**: the one model on this roster whose reasoning was actually
  removed lost a third of its solved tasks, so a Muse pin is no longer plausibly free
  decode time — it is a capability trade, and the fog patch should be read that way.
  Muse is the model with the *most* to lose, being the only one clearing 9/12. If this
  ever becomes a ticket it needs the same shape W19 had: a floor fixed before the run.
- **Muse Glimmer under LM Studio, if a runtime ever ships mlx_vlm ≥ 0.6.12.** W10 makes
  the model oMLX-only today, and W10 deleted its GGUF, so the cross-runtime A/B that
  constraint 10 wants is unavailable for it. This graduates only on an external release,
  so it cannot be a ticket now. The check is one command: `lms runtime update`, then
  `lms load muse-glimmer-30b`. **W16 sharpens what "external" means**: a *fresh* LM Studio
  0.4.21 install still ships `mlx-llm 1.11.0` carrying mlx_vlm 0.6.5, so reinstalling or
  updating the **app** moves nothing. Only a **backend** release does.
- **Nothing in this repo owns the LM Studio side of the A/B, and W9 found it needs two
  steps, not one.** W16 saw the reinstalled app ignore its own `downloadsFolder` and index
  nothing until the model directories were linked into `~/.lmstudio/models`. **W9 finds
  that half repaired on its own** — `lms ls` now reports 6 models read straight from the HF
  cache, Muse Glimmer and the DFlash drafter included, while only the two W16 symlinks
  exist — so the setting is honoured again and the links may be redundant. But W9 adds a
  second unmanaged step that is **not** optional: `limit.context` in `opencode.json` is a
  client budget only, and LM Studio fixes context at **load** time, so a bare
  `lms load zai-org/glm-4.7-flash` fails every agentic turn in two seconds until it is
  loaded with `--context-length 32768`. **W18 settles the open half and closes this
  patch.** It hung on how much the A/B is really used, and the user answers: little —
  opencode almost always. So an `ai.sh`-owned `lms load` helper is now Out of scope, and
  what stays here is a **fact rather than fog**: anyone running the A/B by hand must load
  with an explicit `--context-length`, or every agentic turn fails in two seconds.
- ~~**The opencode-mem summarizer against a VLM-class model.**~~ **Graduated by W18**
  and **closed by W20**: the summarizer stays on the session's own model, with the
  plugin's abort raised to 180 s, iterations cut to 2 and output capped at 2,048.
  Nothing here remains open — but W20 leaves one thing it did **not** measure, kept as
  fog rather than a ticket because it needs a real session, not a synthetic one:
  **how often a capture actually needs a second iteration.** `autoCaptureMaxIterations:
  2` is reasoned from Muse producing a valid tool call on 8 of 8 *solo* runs, not from
  observed retries. If captures start failing in use, that number is the first suspect
  and the fix is one config value. It is not sharp enough to ticket until the memory
  store shows a miss.
- ~~**Long-context capability, for any model.**~~ **Graduated by W17, closed by W21.** The
  retrieval half is settled outright — 36 of 36 at ~22k, no model loses an exact fact across
  the window, and Muse's 13-of-52 sliding-attention structure costs it nothing there. The
  capability half is settled as a **tie**: at ~17.6k the three models sit inside one
  another's noise band, so the default rests on the pre-registered floor rather than on a
  measured lead.
- **Whether a larger suite could separate the three at ~17.6k — and what that would cost.**
  New in W21, and the honest residue of it. W21 ran 9 runs over 3 tasks and every resulting
  gap was one or two, which is exactly the size W14 declares as noise, so the suite answered
  "indistinguishable" partly because it is too small to answer anything else. **Bonsai is
  the reason this is not idle**: it draws level with Muse on solved tasks (8/9 each) while
  costing **2.31 min/solved against 3.19**, and it degrades least with context (1.12×
  against Muse's 1.39× and GLM's 1.73×). If that survives a larger suite it is a real case
  for moving the default, and W21's floor would have to be re-fixed before such a run. It is
  not a ticket because nobody has priced the suite that *could* separate them: the question
  is how many runs resolve a one-task gap, and whether those hours are worth a default that
  already works. **What it must not become is a re-run of the same 9-run shape**, which
  would produce another tie and cost another two hours.
- **Every per-turn cost estimate on this map was computed at short-context decode rates.**
  New in W21, which measured all three models losing about two-thirds of their decode rate
  between a ~1.5k prompt and a 17–22k one. `CLAUDE.md` now carries both figures, so the
  *documentation* is repaired. What is not repaired is the reasoning built on the old
  numbers — W18's min/solved ranking, the door-charge-buys-a-session argument, and W20's
  summarizer timings were all derived at rates ~3× higher than an agentic turn sees. W21
  re-derived min/solved at length for its own trimmed suite and the order changed; nothing
  has re-derived the rest. Not a ticket because no live decision turns on it, and because
  the **relative** order is unchanged — GLM keeps its ~2× decode lead at every size
  measured. It becomes one if someone re-opens the default or the summarizer.
- **An empty response whenever history carries a prior tool call.** New in W22, found while
  building its loop and deliberately not chased. A request whose messages include an assistant
  `tool_calls` entry plus its `tool` result came back completely empty — `finish_reason: stop`,
  no content, no `reasoning_content`, no tool calls — with `arguments` sent as a JSON string
  **and** as a dict, so it is not the wire-format question it looks like. That is the
  multi-turn path, i.e. every turn after the first, which makes it alarming on its face. It is
  fog rather than a ticket because it may be a flaw in the probe's own message shape: real
  opencode sessions plainly do work multi-turn, and W14 and W21 both ran multi-turn suites to
  completion. It becomes a ticket the moment a real session shows a silent empty turn. The
  probe is `assets/w22-muse-toolcall/`, and the first move is to compare its message array
  against what opencode actually puts on the wire.
- **Whether the serve-check gate should assert the tool-call wire format.** New in W22, which
  is the reason it exists. The gate asserts `finish_reason: stop`, non-empty `content`,
  reasoning split out, and that a tool call *parses* — and every model passed it while Muse's
  tool calls were arriving corrupt in real use, because the gate runs one simple call at a
  short prompt. What a stronger gate would assert is clear enough (the returned tool name is
  one of the declared tools, verbatim; no special token survives anywhere in name, arguments
  or content; parallel calls all parse), but two things are not: whether it belongs in the
  serve check or in a separate wire-format probe, and whether it can be made to fire at all,
  given W22's defect **never reproduced live** in any configuration tried. A gate that cannot
  go red on the one defect it was written for is worse than no gate, because it reads as
  coverage. Pricing that is the work, and nobody has.

## Out of scope

- **Vision and multimodal use.** Bonsai and Muse Glimmer both load vision towers.
  This map serves them as coding models only.
- **Removing the Vercel gateway default or the `@advisor` cloud path.** Neither is
  part of the local roster; the gateway keeps a bare `opencode` useful and the
  advisor is a deliberate, audited egress path with its own kill switch.
- **Deleting the MCP kill-switch machinery.** It costs nothing while idle.
- **Moving `ai` onto LM Studio as its runtime.** oMLX supplies the two-tier KV cache,
  one process for LLM plus embeddings, and continuous batching.
- **Replacing a roster model with a *different* model.** W13 draws the scope line: a new
  architecture needs its own serve check and its own measurement session, so it is a
  fresh map. A **re-quant of a model already on the roster** stays in scope, because the
  serve check is largely re-usable and it can attack an open blocker — see option D on
  [Decide GLM's context cap against oMLX's 7x MLA over-count](tickets/12-glm-context-cap.md).
- **Making any roster model prefill faster.** W17 shows prefill speed, not memory, is
  what caps usable context on this box. It also closes every route to changing it here:
  Muse has no custom kernel at all (W7), Bonsai's is decode-only (W6), and GLM's
  `glm_moe_dsa` binds to a different `model_type` and is decode-shaped anyway (W17). What
  remains is a faster-prefilling model, and **replacing a roster model with a different
  model is already out of scope**. So the ~32,300-token two-minute boundary is a property
  of this box and this roster, not an open question.
- **An `ai.sh`-owned `lms load` helper for the LM Studio A/B.** W9 left it open, hanging on
  how much the A/B is really used; W18 asked, and the user runs opencode almost always. So
  the launcher does not learn to link and load models for a second runtime it does not
  drive. **W9's `lmstudio` provider block stays** — it works, it costs nothing, and the
  A/B remains available by hand with an explicit `lms load --context-length`.
- **Reclaiming disk by deleting APFS local snapshots.** W4 found seven Time Machine
  local snapshots holding the 15 GB it pruned. Deleting them is system maintenance and
  destroys backup history, so it belongs to the user, not to this map. The space is
  purgeable, so macOS releases it under pressure on its own.
