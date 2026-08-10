# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Bash tool (`ai.sh`) that launches a local [oMLX](https://github.com/jundot/omlx) inference server and connects [opencode](https://opencode.ai) (the sst/opencode build) to it. The local model is Qwen 3.6 35B-A3B in a flat MLX **6-bit** quant by default (or, with `-l`, the same model in oMLX's native **oQ6** quant with MTP speculative decode). oMLX is a native Apple-Silicon server whose two-tier KV cache (hot RAM + cold SSD) restores recurring prompt prefixes from disk instead of recomputing them, collapsing agentic time-to-first-token from ~30s to ~1s, and it serves the LLM **and** the embedding model (bge-m3) from one process with continuous batching. opencode has persistent cross-session memory via the `opencode-mem` plugin (local SQLite; embeddings + summarizer run on oMLX — see the Memory section). Designed for Apple Silicon Macs (M4 Max with 64GB RAM assumed).

## Usage

```bash
bash ai.sh              # Qwen 3.6 35B-A3B 6-bit (local oMLX) + opencode
bash ai.sh -l           # Qwen 3.6 35B-A3B oQ6 +MTP (speculative decode) + opencode
bash ai.sh -g           # Gemma 4 12B QAT+OptiQ 4-bit (small, dense) + opencode
bash ai.sh --muse       # Muse Glimmer 30B oQ4e (dense, newer oMLX) + opencode
bash ai.sh --no-hybrid  # Disable the default @advisor cloud-Claude subagent
bash ai.sh -k           # Kill the local server
bash ai.sh -h           # Show help
bash ai.sh -- --flag    # Pass args through to the frontend
source ai.sh && ai      # Source as a function
```

### Default model — Qwen 3.6 35B-A3B 6-bit

The default `ai` runs **`mlx-community/Qwen3.6-35B-A3B-6bit`** — the A3B MoE (3B active) in a flat MLX **6-bit** quant. ~27.5 GB resident. It's the everyday coder: a broad **65,536** context window (declared in `opencode.json` under provider `mlx`), no per-model oMLX settings to enable, and **auto-downloaded on first use** (see Models below). For the faster oQ6 +MTP build of the same model, use `-l`.

### `-l` (lite) — oQ6 +MTP speculative-decode build

`ai -l` (alias `--lite`) runs **`Jundot/Qwen3.6-35B-A3B-oQ6-mtp`** — the same A3B MoE, but in oMLX's native **oQ6** quant (data-driven mixed-precision: bits allocated where layer-sensitivity calibration says they matter) rather than a flat MLX 6-bit, with the model's **MTP** (multi-token prediction) heads preserved. ~30 GB resident. Faster decode than the flat 6-bit default when MTP engages.

**MTP is off by default in oMLX** even when the weights carry MTP heads — it's a per-model setting (`mtp_enabled`), not an `omlx serve` flag. `ai.sh` enables it on launch via `scripts/patch-omlx-mtp.mjs` (see the model_settings.json side-effect below). With it on, oMLX runs a draft+verify speculative-decode loop for **singleton decode when batch rows align** — so a coding turn overlapping the opencode-mem summarizer (the 2nd concurrent slot) falls back to normal decode for that window; the speedup is real but intermittent.

The model is **auto-downloaded on first use** (see Models below) and declared in `opencode.json` under provider `mlx` at a **49,152** context cap (see Context window — KV is cheap for this model, so the cap is set by the prefill transient, not KV size; it sits below the default's 65 k because oQ6-mtp's +2.5 GB resident leaves less prefill headroom).

**`-l` runs MCP-free.** Unlike the default (which keeps smart-coding RAG and any other MCP), lite disables **every** MCP server for the session — no smart-coding indexing, no chrome-devtools. `ai.sh` does this without editing `opencode.json`: it builds an inline config marking `enabled:false` for each server keyed under `mcp` in `opencode.json` and passes it via **`OPENCODE_CONFIG_CONTENT`**, which opencode deep-merges *last* (later wins) over the global config — so the override is session-scoped and automatically covers any MCP added to `opencode.json` later. The `opencode-mem` plugin and the `@advisor` subagent are unaffected (they're not MCP servers).

### `-g` / `--gemma` — Gemma 4 12B QAT+OptiQ 4-bit (small, dense)

`ai -g` (aliases `--gemma`, `-gemma`) runs **`mlx-community/gemma-4-12B-it-qat-OptiQ-4bit`** — Google's official Gemma 4 12B *instruct* weights, quantized from a **QAT** (quantization-aware-trained) base with **OptiQ** mixed precision: a 4-bit floor plus **329 per-layer overrides** placed by sensitivity calibration, rather than the flat quant the default uses. **9.00 GB on disk, ~11 GB resident** — roughly a third of the Qwen default's ~27.5 GB. Purely additive: Qwen stays the default, and `-g` is mutually exclusive with `-l` (combining them is a hard error, since the wrong pick costs a multi-GB download or a server restart).

The quant was chosen over the flat 6-bit (9.73 GB) at 0.73 GB *less*, on the reasoning that a QAT base is trained for low-bit and OptiQ allocates bits where calibration says they matter. Available `mlx-community/gemma-4-12B-it-*` builds for reference:

| Quant | Weights | Scheme |
|---|---|---|
| `mxfp4` | 6.37 GB | MX 4-bit |
| `4bit` | 6.74 GB | flat affine |
| `5bit` | 8.23 GB | flat, 0 overrides |
| **`qat-OptiQ-4bit`** | **9.00 GB** | **4-bit + 329 per-layer overrides on a QAT base — used by `-g`** |
| `6bit` | 9.73 GB | flat, 0 overrides |
| `8bit` | 12.72 GB | flat affine |
| `bf16` | 23.92 GB | — |

**The central caveat: dense 12B vs 35B-A3B MoE.** Smaller on disk does **not** mean faster here. Gemma 4 12B is *dense* — every decoded token reads all ~9 GB of weights — whereas Qwen 3.6 35B-A3B activates only ~3B params per token. Prefill is roughly **4× the FLOPs per token**. Expect `-g` to decode *slower* than the default despite its far smaller footprint; the win it buys is ~17 GB of freed memory headroom, not speed.

Two further caveats worth stating plainly:

- **The quality claim is unverified.** `google/gemma-4-12B-it` was published 2026-05-23, at the assistant knowledge cutoff, and there is no benchmark data here backing "Gemma 4 12B beats Qwen 3.6 35B-A3B" for coding. This profile exists to *measure*, not because it is known to be better.
- **Third-party quant ambiguity.** Because OptiQ was picked over the official flat quant, a disappointing result is ambiguous between the model and the quantization.

**KV cache is near-free.** 48 layers: **40 `sliding_attention`** (`sliding_window: 1024`, 8 KV heads × 256 head_dim) whose KV is window-capped at a **fixed ~335 MB regardless of context length**, plus **8 `full_attention`** layers with `num_global_key_value_heads: 1`, `global_head_dim: 512`, and `attention_k_eq_v: true` (K and V share one tensor) ⇒ ~**8 KB/token**. Total ≈ **0.9 GB at 65 k**, 1.4 GB at 128 k, 2.4 GB at 262 k against a native `max_position_embeddings` of 262 144. Memory is *not* the binding constraint for this model — prefill time is.

Context is nonetheless capped at **65,536** in `opencode.json`, matching the default exactly so `-g` vs `ai` is a clean single-variable comparison. **Long-range-recall caveat:** only 8 of 48 layers see the whole window; the other 40 are limited to a 1024-token sliding window, so recall of detail far back in a long session is structurally weaker than the layer count suggests.

**MCPs stay enabled** under `-g` (unlike `-l`). This is free — the MCP kill-switch in `ai.sh` is gated on the `lite` profile specifically, so `gemma` falls through to the normal branch — and it's safe despite Gemma 4 being fussy about tool schemas, because **oMLX repairs them server-side**: `enrich_tool_params_for_gemma4` / `restore_gemma4_param_names` (`omlx/api/tool_calling.py`, called from `omlx/server.py`) rename params colliding with JSON-Schema keywords (`description` → `param_description`) and inject missing descriptions, MCP-supplied schemas included. Gemma 4 is first-class in oMLX generally (`gemma4_unified` registered in `omlx/model_discovery.py`; VLM engine handles it including audio).

**Thinking must be pinned off explicitly — oMLX's auto-detection does not reach the chat endpoint.** Gemma 4's chat template defaults thinking off (`enable_thinking | default(false)`) and oMLX's `detect_thinking_default()` correctly returns `False` for this model, but that detection is never wired into `/v1/chat/completions`: `enable_thinking` is only injected into the template kwargs when a *thinking budget* is set. Measured on an unqualified chat request, the model returned **100% `reasoning_content` and empty `content`**, running to the `max_tokens` cap without ever answering — reproduced at 400, 600 and 2000 tokens. (The same prompt rendered by hand and posted to `/v1/completions` answers directly, so this is the endpoint's default, not the weights.) `ai.sh` therefore writes `enable_thinking: false` for this model via `scripts/patch-omlx-mtp.mjs`; `ms.enable_thinking` takes precedence over `chat_template_kwargs` in `omlx/server.py`, making per-model settings the one reliable place to pin it. With it applied: `finish_reason: stop`, zero reasoning tokens, a real answer.

**Settings must be keyed by the model's *directory leaf*, not the two-level id.** oMLX registers models under their directory name beneath `--model-dir`, so `/v1/models` lists `gemma-4-12B-it-qat-OptiQ-4bit`, not `mlx-community/gemma-4-12B-it-qat-OptiQ-4bit`. `EnginePool.resolve_model_id()` accepts the two-level id we send by *stripping everything before the first `/`* and re-matching — and the resulting bare id is what `model_settings.json` is then keyed against. A settings entry under the two-level id is silently never consulted (verified: `enable_thinking` under the two-level key had no effect; under the leaf it took hold immediately). `patch-omlx-mtp.mjs` now writes **both** spellings for every model in its `DESIRED` map. **This also means the `-l` build's `mtp_enabled` entry, keyed `Jundot/Qwen3.6-35B-A3B-oQ6-mtp`, had never been matched** — MTP was silently inert for `-l`, which is exactly the failure mode the MTP section warns is hard to attribute. The both-spellings fix covers it, but it is unverified against real weights (the Qwen snapshots are currently absent from this box).

**Deliberately not wired up** (each deferred so the first `-g` run is a clean baseline): no MTP drafter (oMLX supports one via `vlm_mtp_enabled` / `vlm_mtp_draft_model`, and `mlx-community/gemma-4-12B-it-assistant-8bit` is a valid `gemma4_unified_assistant` drafter at 0.45 GB — but `load_vlm_mtp_drafter` **soft-fails**, so a misconfigured drafter is indistinguishable from "the model is just slow"); `OMLX_HOT_CACHE` stays at 8 GB despite the freed headroom.

**Measured baseline** (first run, this box, short prompts, MCP-free measurement path): **9.10 GB resident** with the model loaded, **~44 tok/s** decode, steady across three 400–500-token turns (43.66 / 43.91 / 44.18); cold model load ~2.0–2.3 s, and no measurable load cost on subsequent turns. Resident sits a little under the ~11 GB estimate because these prompts carry almost no KV; add ~0.9 GB for a full 65 k window.

### `--muse` — Muse Glimmer 30B oQ4e (dense, runs a second oMLX build)

`ai --muse` runs **`Jundot/Muse-Glimmer-30B-oQ4e`** — Meta's Muse Glimmer 30B in oMLX's native **oQ** quant, built by the oMLX author with oMLX 0.5.8.dev1. **20.28 GB on disk**, 5 shards. Auto-downloaded on first use.

**Read "mixed precision" narrowly here.** The quant is a 4-bit affine floor at group size 64 with just **17 per-layer overrides** — 13 at 5-bit, 3 at 6-bit, 1 at 8-bit — placed on `embed_tokens` and on early-layer `mlp.down_proj` / `self_attn.o_proj` by an importance matrix calibrated on `oqe_code_multilingual` (128 samples × 512 tokens; the report ships as `oq_imatrix_report.json`). For scale, `-g`'s Gemma OptiQ build carries **329** overrides. Against ~2272 tensors, 17 lifts make this much closer to a flat 4-bit than the phrase "mixed precision" implies — so if it underperforms, do not assume the calibration was the deciding factor.

**This profile is unproven. It exists to measure.** No benchmark data here supports "Muse Glimmer beats Qwen 3.6 35B-A3B" for coding. It is opt-in and changes no default. `--muse` is mutually exclusive with `-l` and `-g`.

**It runs a second oMLX build, and that is the whole reason the profile is structured the way it is.** Muse Glimmer support landed upstream in `6ee393d4` (VLM support), `39bb1784` (DFlash speculative decode) and `9a57d63d` (centered-RMSNorm FP32 operation order) — **2190 commits** after the pinned `9aa73b1` / `omlx 0.4.2rc1` the other profiles run. Upstream adds `omlx/adapter/muse_glimmer.py` (the ATEM channel parser) and a **vendored mlx-vlm patch** at `omlx/patches/mlx_vlm_muse_glimmer_compat/`; upstream mlx-vlm has no `muse_glimmer` module, so only the oMLX upgrade supplies it. The pins move too (`mlx` 0.31.2 → 0.32.0, `transformers` 5.10.2 → >=5.12.1), which makes it a venv rebuild rather than an upgrade.

So the layout is **two checkouts and two venvs**, not one upgraded in place:

| | Checkout | venv | KV cache | Budget |
|---|---|---|---|---|
| `ai` / `-l` / `-g` | `~/.omlx/src` @ `9aa73b1` | `~/.omlx/venv` | `~/.omlx/cache` | 15 GB |
| `--muse` | `~/.omlx/src-next` @ `origin/main` | `~/.omlx/venv-next` | `~/.omlx/cache-next` | 25 GB |

A second venv **alone would isolate nothing**: `~/.omlx/venv` is an *editable* install of `~/.omlx/src`, so pulling that checkout would make the old venv run the new code at once. The second checkout is what makes the other profiles a real rollback path. Costs ~1 GB.

**The two builds must not share a cache directory** — but for the mundane reason, not the format one. Both are checked in `omlx/cache/paged_ssd_cache.py`:

- **Format is mostly compatible, contrary to what you might assume.** Both builds define `_CACHE_FORMAT_VERSION = "3"`. The pinned build reads `{"2","3"}`; the new one reads `{"2","3","4","5"}` and writes `"3"` by default. It writes `"5"` only when `gdn_ssd_split_enabled` (an env-gated setting that defaults to `False` in `omlx/config.py` and which `ai.sh` never sets), and `"4"` only for a `PoolingCache` append-only delta. So a block the pinned build rejects is the exception, not the rule — and a rejected block is just a cache miss, which is the safe failure anyway.
- **The real reason is mutual eviction.** Both servers run `_prune_cache` oldest-first down to *their own* budget at every start. Point them at one directory and each start deletes the other's warm blocks, which destroys the prefix-cache win that collapses agentic time-to-first-token from ~30s to ~1s. This one is unconditional.

Hence `cache-next`. The two budgets sum to the 40 GB the single cache used before the split, so total disk use is unchanged; the first run after this change prunes the existing 22 GB cache down to 15 GB.

`~/.omlx/model_settings.json` **is** shared safely: `SETTINGS_VERSION = 1` on both builds and `from_dict` drops unknown fields. `bge-m3` also survives the upgrade (still an `XLMRobertaModel` in upstream `EMBEDDING_ARCHITECTURES`) — which matters, because it serves smart-coding RAG *and* `opencode-mem`, so an embedding regression would break memory and RAG, not just chat. Every server flag `ai.sh` passes still exists upstream.

**Architecture caveats — read these before reading any measurement:**

- **Dense 30B, not a MoE.** Every decoded token reads all the weights, against ~3B active parameters for Qwen 35B-A3B. Expect a large decode slowdown. This is the same trap as `-g`: smaller on disk does not mean faster.
- **Long-range recall is structurally weak.** Only **13 of 52** layers are `full_attention`; the other 39 are `sliding_attention` with `sliding_window: 2048`. Gemma's equivalent caveat is 8 of 48 at window 1024. Recall of detail far back in a long session is weaker than the layer count suggests.
- **Vision weights are dead weight.** The quant carries a ~1.85B vision tower (~0.9 GB at 4-bit; 806 `vision_tower.*` tensors against 1463 `language_model.*`). oMLX registers `muse_glimmer` in `VLM_ARCHITECTURES` and always uses the VLM engine — no runtime flag skips the tower. Accepted rather than hand-stripping tensors, since a ready-made quant is the lower-risk path.
- Text stack: 52 layers, hidden 6656, 32 heads, **2 KV heads**, head_dim 128, vocab 202048, `max_position_embeddings` 131072.

**KV is cheap:** ~13 KB/token plus ~82 MB fixed ⇒ ~0.85 GB at 65 k. Context is capped at **65,536 / 8,192 output** with `"temperature": false`, matching the Qwen default exactly so `ai` vs `--muse` stays a single-variable comparison. `OMLX_HOT_CACHE` stays at 8 GB and `OMLX_MAX_CONCURRENT` at 2 during the measurement.

**The primary risk is tool-call parsing, not speed.** The chat format is Onyx/ATEM (`<|start|>role<|message|>BODY<|eom|>`), and tool calls are **XML**, not JSON (`<atem:function_calls><atem:invoke name="…">`) — the model's own prompt states the payload "is not expected to be valid XML and is parsed with regular expressions". `omlx/adapter/muse_glimmer.py` is days old. Reasoning goes to a `to=self` channel that oMLX surfaces as `reasoning_content`, and the chat template defaults `reasoning_strength` to `high` when the caller passes nothing — which opencode does. oMLX has no `reasoning_strength` field; its knobs are `enable_thinking`, `thinking_budget_enabled`, `thinking_budget_tokens` and `reasoning_parser`.

**Phase-1 smoke test (not the measurement).** The new build serves the model and the two-level id resolves: a request for `Jundot/Muse-Glimmer-30B-oQ4e` is matched to the `Muse-Glimmer-30B-oQ4e` directory leaf that `/v1/models` actually lists, and the response echoes the two-level id back. Cold model load **5.34 s**. Decode **~21.5–21.9 tok/s** on trivial prompts — above the ≥15 tok/s gate, but on ~60-token prompts with no KV, so it is not a substitute for a real agentic turn. Cache isolation holds: a `--muse` server writes only to `cache-next` and left the 22 GB `cache` untouched. Resident memory was **not** measured — MLX allocates through Metal unified memory, so `ps` RSS reported 2.77 GB against a 20.3 GB model and is meaningless here.

**One trap worth knowing before you debug this profile.** At `max_tokens: 64` the model returns `content: None`, a full `reasoning_content`, and `finish_reason: length` — which looks exactly like the Gemma 4 failure recorded above. **It is not the same bug.** Raise the budget and it terminates normally: at 600 and 2000 tokens it returned `finish_reason: stop` with `content: "OK"` after ~340–400 characters of reasoning. Muse Glimmer simply reasons before answering, so any budget smaller than its reasoning prefix truncates mid-thought. Do not reach for `enable_thinking: false` on this evidence.

**Reasoning is capped to `medium` via `model_settings.json` — measured, not guessed.** The template line is `reasoning_strength if reasoning_strength is defined and reasoning_strength else 'high'`, and opencode passes nothing, so the shipped default is **high**. Measured on "What are you?" against the live server:

| `reasoning_strength` | Wall time | Output tokens | Reasoning share |
|---|---|---|---|
| `high` (default) | 9.61 s | 214 | ~85% |
| `medium` (**pinned**) | 4.29 s | 84 | ~69% |
| `low` | 3.74 s | 73 | ~40% |

Decode itself is healthy at **~20–22 tok/s**; the latency is token *volume*, not speed. `high` spent 13.7 s "thinking" before a one-line answer in a real session. `medium` is pinned as the hedge — it keeps deliberation that may earn its keep on coding turns while removing most of the stall.

**The knob is not `enable_thinking`.** Unlike `-g`, this model routes reasoning through a channel oMLX parses on purpose, so switching thinking off is a different and wrong fix. oMLX has no `reasoning_strength` field either; the value reaches the template through `ModelSettings.chat_template_kwargs`, which `merge_chat_template_request_kwargs()` folds in at *lowest* precedence — a per-request kwarg would still win, which is why opencode sending nothing is what makes the pin effective. `scripts/patch-omlx-mtp.mjs` writes it under both the two-level id and the directory leaf, as every entry must be.

**Settings are read at model load, and a same-model relaunch does not restart the server.** `ai --muse` twice in a row hits the "Server already running" branch, so a changed setting is silently not picked up. Run `ai -k` first.

**Gates before this profile could become the default:** ≥15 tok/s decode; tool calls parse across one full agentic turn with the smart-coding MCP on; no memory-guard eviction on a 30k-token prefill. Measured against Qwen on the same prompts, in the same session, with `opencode-mem` auto-capture off and then on.

**Deliberately not wired up:** the **DFlash drafter** (oMLX supports it for this model — `omlx/engine/dflash.py`; routing keys on `config_model_type == "muse_glimmer_assistant"`, *not* the historic "`-assistant` means MTP" name rule; `meta-models/Muse-Glimmer-30B-assistant` is 5.11 GB bf16 with no MLX quant, but oMLX quantizes the drafter itself via `dflash_draft_quant_weight_bits`). Before enabling it, disable `dflash_ssd_cache` or exclude its path from `_prune_cache` — **DFlash's L2 cache writes into the same SSD cache directory `_prune_cache` deletes from blindly.** Also deferred: a local **oQ text-only** build (oMLX's oQ pipeline takes a `text_only` parameter in `omlx/admin/oq_manager.py` and applies the Muse compat patch in `omlx/oq.py`), which would drop the dead vision tower but needs the 59.58 GB source and a disk cleanup first.

**On the choice of weights.** `mlx-community/Muse-Glimmer-30B-4bit` (21.38 GB, flat) is the only other real MLX build; the `-5bit`, `-6bit`, `-8bit`, `-bf16`, `-mxfp4`, `-mxfp8` and `-nvfp4` repos under `mlx-community` are **empty placeholders** holding just `.gitattributes` and `README.md`. A real 6-bit exists at `georgeis55/Muse-Glimmer-30B-MLX-6bit` (26.42 GB) but was rejected on unknown provenance for a brand-new architecture. oQ4e won over the flat 4-bit on three points: it is built by the server author with the exact oMLX version this profile runs, its imatrix is calibrated on code, and it is 1.1 GB smaller. Two costs come with that choice. First, **attribution ambiguity** — a disappointing result cannot cleanly separate the model, the quant and the days-old adapter. Second, the quant had **0 downloads and was hours old** when it was picked, so no one else had run it. If the profile misbehaves, `mlx-community/Muse-Glimmer-30B-4bit` is the control: same architecture, flat quant, the path other users take.

### Hybrid cloud advisor mode (default on; `--no-hybrid` to disable)

The hybrid cloud advisor is **on by default** (the default model and `-l`). It keeps the local Qwen as the primary coding agent but adds a **read-only, prompt-only cloud-Claude advisor** you summon by hand with `@advisor`. The bulk of the work stays on-box; only the snippet/question you explicitly hand the advisor leaves the machine, for a real cloud-Opus second opinion on a hard architectural call or a correctness/security review. `--no-hybrid` disables it. The legacy `-hybrid` flag is still accepted (it now just makes the default explicit). Requires a one-time `opencode auth login` → Anthropic (OAuth, uses your Claude plan — **no API key, no per-token bill**); launches warn if that login is missing.

Three independent privacy controls (defense in depth):

1. **Gating** — the advisor agent (`agents/advisor.md`) is symlinked into `~/.config/opencode/agents/` **only** when the advisor is active; every `--no-hybrid` launch *removes* it, so a no-advisor launch has no agent referencing the `anthropic` provider and therefore **no egress path to the cloud at all**.
2. **Manual** — `opencode.json` sets `permission.task: "ask"`, so even if the local model tries to delegate to the advisor, opencode prompts before anything leaves the box. The advisor is `mode: subagent` (never the primary), invoked via `@advisor`.
3. **Prompt-only** — `advisor.md` denies **every** tool (`read`/`grep`/`glob`/`bash`/`edit`/`write`/…), so the advisor can reason only about the text you hand it — it cannot open files to widen the egress.

The advisor runs on opencode's **built-in `anthropic` provider** (real `api.anthropic.com`), pinned to `anthropic/claude-opus-4-8` — this is **not** the local oMLX endpoint. Every advisor call is recorded by `plugins/advisor-egress-log.js` (see Post-edit checks for the plugin-loading mechanism) to **`logs/advisor-egress.jsonl`** — one append-only JSON line per call (`ts`, `sessionID`, full outbound `prompt`). It's named `.jsonl`, not `.log`, on purpose: `ai.sh` prunes `logs/*.log` older than 14 days and an audit trail must outlive that. `ai.sh` passes the path to the plugin via `ADVISOR_EGRESS_LOG` (derived from `AI_LOG_DIR`); the egress plugin is symlinked in only when the advisor is active and removed otherwise, alongside the agent.

## Validating changes

There is no build step or test framework — this repo is a Bash launcher (`ai.sh`), a
few opencode plugins (`plugins/*.js`, ESM), agent definitions (`agents/*.md`), and
idempotent patch scripts (`scripts/*.mjs`). There is no `package.json`; don't reach
for `npm test`. Validate edits with:

- `bash -n ai.sh` — syntax-check the launcher.
- `node --check plugins/<file>.js` / `node --check scripts/<file>.mjs` — syntax-check a plugin or patch script.
- `python3 -m json.tool opencode.json >/dev/null` — validate the opencode config JSON.
- **Unit-test the oMLX settings patch in isolation**: `node scripts/patch-omlx-mtp.mjs /tmp/ms.json` against a throwaway path and assert the merge — fresh-create, idempotent re-run (no rewrite), preserving a pre-existing model/key, and recovering from a corrupt file. No oMLX needed.
- `opencode agent list` — after editing `agents/*.md` or `opencode.json`, confirm the
  agent loads and its `model`/permissions resolve without error (e.g. `advisor` shows
  as `advisor (subagent)`). Custom agents/subagents load from `~/.config/opencode/agents/`.
- **Unit-test a plugin hook in isolation** (no oMLX, no opencode, no cloud call):
  `import` the plugin and invoke the returned hook with a synthetic `(input, output)`.
  The advisor egress logger was validated this way — fire `chat.message` /
  `tool.execute.before` with a fake `agent:"advisor"` message and assert the log line
  (and that non-advisor sessions don't write). See `plugins/advisor-egress-log.js`.
- **Restart to load changes**: opencode loads plugins and agents only at startup, so
  exit and re-run `ai` to pick up edits to `plugins/*.js`, `agents/*.md`, or symlinks.

The `post-edit-check` plugin (below) runs ESLint/tsc/Prettier on JS/TS edits in the
*target* projects opencode opens — it cleanly no-ops on this repo (no eslint/tsconfig/
prettier here).

## Architecture

### `ai.sh` — Single Bash function `ai()`

1. **Server lifecycle**:
   - `_resolve_runtime` — picks the oMLX **binary**, KV-cache **directory** and cache **budget** for the selected profile, after the profile dispatch. `OMLX_BIN` / `OMLX_CACHE_DIR` / `OMLX_SSD_CACHE_MAX` still override, but they apply to every profile at once. The profile's own venv is preferred over an `omlx` on PATH, because a PATH build is whatever was installed last and the pinned build cannot serve Muse Glimmer at all.
   - `_start_server` — runs `omlx serve --model-dir … --paged-ssd-cache-dir …` with tuned cache/memory flags, using the binary `_resolve_runtime` picked. oMLX discovers models from `--model-dir` subdirectories, so no `--model` is passed; opencode picks the model per request.
   - `_wait_for_server` — polls `/v1/models` with spinner, opens tmux log pane if in tmux
   - `_kill_server` — kills by PID file then port scan (only targets python/mlx/omlx processes — the oMLX process renames itself to `omlx-server`)
   - On a model switch the server is killed/restarted automatically (state file `$AI_STATE_DIR/omlx-model` vs the requested id). The state file records **two** lines — model id and the oMLX binary serving it — and a difference in *either* forces the restart. The binary matters as much as the model now that profiles run oMLX builds 2190 commits apart: a same-model/different-binary case would otherwise leave the pinned server answering for a model it cannot load. A state file written before the binary was recorded reads as a mismatch and restarts once. But oMLX is multi-model and lazy-loads whatever id a request asks for, so a **lingering opencode from a previous `ai`/`ai -l` run** keeps requesting its old model and oMLX loads it alongside the new one — two ~28-30GB LLMs can't coexist under the memory guard, so it thrashes (evict/reload) and stalls or `507`s requests mid-turn (the agent "chokes"). `_warn_model_conflict` detects this — it reads each running opencode's `-m mlx/<id>` arg and warns if any differs from the model being launched, pointing the user to close that session and `ai -k`. (ai.sh can't fix it automatically — it can't control the other client.)
2. **RAG**: Checks for `smart-coding-mcp` on launch (auto-indexes via opencode MCP config). The default keeps RAG (index built once, then cheap); **`-l` disables all MCPs** (RAG included) via `OPENCODE_CONFIG_CONTENT` — see the `-l` section.
3. **Frontend launch**: After the server is healthy, runs `opencode -m "mlx/<model-id>"` (configured via `opencode.json`) in the caller's original `$PWD`.
4. **Hybrid advisor** (on by default; off under `--no-hybrid`): symlinks `agents/advisor.md` → `~/.config/opencode/agents/advisor.md` and `plugins/advisor-egress-log.js` → `~/.config/opencode/plugins/`, runs an Anthropic-OAuth preflight warning, and exports `ADVISOR_EGRESS_LOG`. Every non-advisor launch *removes* both symlinks (the airgap guarantee). See the Hybrid cloud advisor mode section above.
5. **Model pinning**: launches `opencode -m mlx/<model-id>`, which **overrides** `opencode.json`'s default `model` (a Vercel AI Gateway model — see below). So `ai` / `-l` / `-g` / `--muse` always run their local oMLX model regardless of what a bare `opencode` defaults to.

### `opencode.json` — OpenCode provider config

Configures the `mlx` provider (local, port 10081), OpenAI-compatible, declaring the 6-bit default, the `-l` oQ6-mtp build and the `-g` Gemma 4 12B build with their context/output limits and timeout. All three set `"temperature": false` so opencode omits the option and oMLX falls back to each model's own `generation_config.json` (for Gemma 4 that's its required `temperature 1.0 / top_k 64 / top_p 0.95` recipe). Also configures smart-coding-mcp for RAG indexing and enables the `opencode-mem` plugin via the top-level `"plugin"` array. `chrome-devtools` MCP is registered but disabled by default — flip `enabled` to true per-session if browser automation is needed. A second provider, `anthropic` (real cloud Claude), is **not** declared here — it's opencode's built-in and resolves via `opencode auth login`; only the `-hybrid` advisor agent references it. The top-level `permission.task: "ask"` enforces the advisor's manual-only rule (see `-hybrid` mode).

**Default model = Vercel AI Gateway.** The top-level `"model"` is **`vercel/alibaba/qwen3.8-max`**, not one of the local `mlx` models. `vercel` is opencode's built-in provider for the [Vercel AI Gateway](https://vercel.com/docs/ai-gateway) — it needs no `provider` block here and resolves via `opencode auth login` → Vercel (API key, stored in `~/.local/share/opencode/auth.json`), exposing ~309 gateway models. So a **bare `opencode`** in any directory gets the gateway model, while **`ai` / `-l` / `-g`** still get their local oMLX model because `ai.sh` passes `-m mlx/<id>` explicitly and a CLI flag beats the config default.

The `mlx` models stay declared for exactly that reason: `mlx` is a custom `@ai-sdk/openai-compatible` provider with no models.dev entry, so `-m mlx/<id>` only resolves while those three entries exist. Deleting them would break `ai.sh`.

`disabled_providers` is `["opencode", "gitlab"]` — `gitlab` is hidden because a `GITLAB_TOKEN` in the environment makes opencode auto-register 23 `duo-chat-*` models that otherwise crowd the picker alongside the gateway's. Removing it from the list brings them back.

### Memory — `opencode-mem` plugin (`opencode-mem.jsonc`)

Persistent cross-session memory for opencode. Activated by `"plugin": ["opencode-mem"]` in `opencode.json`; configured by `opencode-mem.jsonc` in this repo, symlinked to `~/.config/opencode/opencode-mem.jsonc` (same pattern as `opencode.json`). Fully local:

- **Storage**: SQLite (source of truth) at `~/.opencode-mem/data`; macOS uses Homebrew SQLite via `customSqlitePath`. Inspect with `sqlite3` or the web UI at `http://127.0.0.1:4747`.
- **Embeddings**: `bge-m3` (1024-dim, MLX/Metal) served by **oMLX** via `/v1/embeddings`. Setting `embeddingApiUrl` + `embeddingApiKey` in `opencode-mem.jsonc` switches the plugin off its in-process Xenova path onto the oMLX endpoint. (Switching from the old 768-dim nomic embeddings changes dimensions — if recall misbehaves on an existing store, clear `~/.opencode-mem/data` to force re-embedding.)
- **Auto-retain**: `autoCaptureEnabled` summarizes salient turns after idle. The summarizer is pointed at the **local oMLX server** (`memoryApiUrl: http://127.0.0.1:10081/v1`) — so capture stays on-box. It needs the oMLX server up (always true when launched via `ai.sh`). `autoCaptureMaxIterations` is raised to 8 now that oMLX's continuous batching lets the summarizer overlap coding turns instead of fighting a single decode slot.
  - **Input cap (important)**: the summarizer is a raw OpenAI client to oMLX, so it **bypasses opencode.json's context limit**. Its `buildMarkdownContext` includes the full, uncapped assistant text of a turn — and when captures fall behind, the message slice spans much of the conversation. Left unbounded this produced ~120k-token summarizer prefills whose KV cache saturated the memory guard: interactive coding turns got throttled (a 3.8k-token turn took 340s) and concurrent `bge-m3` embedding loads were rejected with HTTP 507 — the agent appeared to "choke" mid-task. `ai.sh` re-applies `scripts/patch-opencode-mem-cap.mjs` on every launch (idempotent; patches both the config-dir install and the plugin cache) to cap the summarizer input to `OPENCODE_MEM_MAX_CONTEXT_CHARS` chars (default 24000 ≈ 6k tokens), keeping the request-framing head and outcome tail and eliding the middle. This is what makes the `autoCaptureMaxIterations: 8` overlap safe.
  - **Summarizer model = session model**: `opencode-mem`'s auto-capture summarizer is pinned (in `opencode-mem.jsonc`) to the default 35B. Under `-m`/`-l` the session runs a *different* model, so when the summarizer asks oMLX for the 35B mid-session, oMLX can't hold two ~20-28GB models under the guard and ping-pongs (evict/reload) into a `507` thrash loop — observed live on a `-m` planner session. `ai.sh` re-applies `scripts/patch-opencode-mem-model.mjs` (idempotent) to make `memoryModel` honor `OPENCODE_MEM_MODEL`, which `ai.sh` sets to the **session's own model id** at launch — so the summarizer reuses the already-loaded model (continuous batching shares it) instead of loading a second one.
  - **Directory exclude (privacy)**: `opencode-mem` has no agent- or directory-scoped opt-out, so `ai.sh` also re-applies `scripts/patch-opencode-mem-exclude.mjs` (idempotent; both install locations). It patches the compiled plugin entry to skip auto-capture, recall injection, and post-compaction restore whenever the session directory is under any prefix in `OPENCODE_MEM_EXCLUDE_DIRS` (colon-separated). Set it to sensitive client-repo roots (via `ai.env`) to keep them out of the memory store entirely; protects every session in those trees.
- **Auto-recall**: `chatMessage` injects top memories at session start; `compaction` restores memories after context compaction.

### Post-edit checks — `post-edit-check` plugin (`plugins/post-edit-check.js`)

Deterministic lint/typecheck enforcement so the agent never leaves broken code behind. Prompt-level rules ("always run the linter") are advisory and get skipped — especially by the local 35B model — so this rides opencode's **`tool.execute.after`** hook, the one lever that can **throw an error back into the agent loop** and force a fix before the turn finishes. Same plugin mechanism as `opencode-mem`.

After every `edit`/`write` to a JS/TS file, scoped to that file's project (nearest `package.json`):

1. **Auto-fix (silent)**: `prettier --write` then `eslint --fix`.
2. **Re-check**: `eslint --format json` (**file-scoped** — only the edited file's own errors block) and `tsc --noEmit` (project-wide; blocks only on type errors in files **the agent has edited this session** — so a break in a file it edited earlier still blocks, but errors in files it never touched, pre-existing or rippled, are surfaced as non-blocking notes).
3. **Block**: any remaining errors are `throw`n as a concise `file:line  rule/code  message` list, forcing the model to fix them.
4. **Capped retries**: after `OPENCODE_LINT_MAX_RETRIES` consecutive throws for the same file+error set, it stops blocking and warns instead — so the local model can't doom-loop on something it can't fix (note `opencode.json` sets `"doom_loop": "allow"`, so this in-plugin cap is the real safeguard).

Auto-detects tooling and **no-ops cleanly** when ESLint config / `tsconfig.json` / Prettier are absent — so non-TS projects and this bash-only repo are unaffected. Binaries resolve from the project's `node_modules/.bin` first, else `npx --no-install` (never auto-installs). tsc uses `--incremental` + a cached `tsBuildInfoFile` so repeated whole-project checks stay cheap on this memory-constrained box (only files changed since the last run are re-checked); it runs after every edit — no time-based skip — so a freshly-introduced type error can never slip through.

tsc is **not** run as `tsc -p tsconfig.json` directly. If a project uses TypeScript **project references** (`references: [...]`, common in monorepos/workspaces), that invocation aborts with `TS6306`/`TS6053` about the *referenced* projects **before type-checking any source** — so the edited file's real errors never surface and the agent's bug slips through (bundlers like CRA/`fork-ts-checker` avoid this by checking the app as one program). Instead the plugin generates a wrapper config in `node_modules/.cache/opencode-tsc-check.json` that `extends` the real tsconfig (absolute path, so `include`/`exclude` resolve correctly) but clears `references` and `composite`, forcing a plain whole-program check. Harmless for non-reference projects (the overrides are no-ops there).

**Global, not per-project**: opencode auto-loads any file in `~/.config/opencode/plugins/` **at startup** (note the directory is **plural** — the singular `"plugin"` key in `opencode.json` is the npm-package array, a *different* mechanism), so `ai.sh` symlinks the repo's `plugins/post-edit-check.js` there on every launch (idempotent `ln -sf`) — it applies in every project opencode opens. It is **not** in `opencode.json`'s `"plugin"` array (that array is for npm-package plugins like `opencode-mem`; plugin-dir files are discovered automatically). Because plugins load only at startup, **opencode must be restarted to pick up the plugin or any change to it.**

## Configuration

Environment variables can be set in `ai.env` or exported before running.

| Variable | Default | Description |
|----------|---------|-------------|
| `AI_DIR` | auto-detected | Base directory of the tool |
| `AI_LOG_DIR` | `$AI_DIR/logs` | Server log directory |
| `AI_STATE_DIR` | `~/.local/state` | State and PID files |
| `AI_PORT` | `10081` | oMLX server port |
| `OMLX_BIN` | the profile's venv (else `omlx` on PATH) | oMLX server binary. `ai`/`-l`/`-g` → `~/.omlx/venv/bin/omlx`; `--muse` → `~/.omlx/venv-next/bin/omlx`. Setting this forces one binary on **every** profile, which breaks `--muse` or breaks the other three |
| `OMLX_MODEL_DIR` | `~/.omlx/models` | Dir oMLX discovers models from (subdirectories) |
| `OMLX_BASE_DIR` | `~/.omlx` | oMLX base path; `$OMLX_BASE_DIR/model_settings.json` is where `patch-omlx-mtp.mjs` writes MTP (`-l`) and thinking-off (`-g`) settings |
| `OMLX_CACHE_DIR` | per profile | Paged SSD KV-cache directory. `ai`/`-l`/`-g` → `~/.omlx/cache`; `--muse` → `~/.omlx/cache-next`. The two oMLX builds disagree on the cache format and both prune oldest-first, so sharing one directory makes them evict each other — setting this collapses the split |
| `OMLX_HOT_CACHE` | `8GB` | In-RAM hot KV-cache tier size (model + tier must fit under the memory guard's soft threshold) |
| `OMLX_SSD_CACHE_MAX` | per profile: `15GB` (`ai`/`-l`/`-g`), `25GB` (`--muse`) | Disk cap for the paged SSD cache (unset, oMLX claims nearly all free disk). The two budgets sum to the 40 GB the single shared cache used before the split |
| `OMLX_CACHE_PRUNE_GB` | numeric part of the cap in force (`15` or `25`) | Prune the on-disk KV cache to this many GB at each server (re)start, oldest-first (mtime = LRU). Derived from the same number the server is given, so the two can never disagree. oMLX's own eviction only tracks its *live* index, so blocks orphaned by prior runs / model-quant switches leak far over the cap (observed 122 GB vs a 40 GB cap); this enforces it. Runs only in `_start_server` (server down), so no live process holds the blocks. Set `0` to disable |
| `OMLX_MEMORY_GUARD_GB` | `48` | Memory ceiling oMLX won't exceed (headroom on 64 GB) |
| `OMLX_MAX_CONCURRENT` | `2` | Max concurrent requests (continuous batching): 1 coding turn + 1 opencode-mem summarizer. Don't set to 1 — memory captures would serialize with coding turns |
| `OPENCODE_MEM_MAX_CONTEXT_CHARS` | `24000` | Char budget the opencode-mem summarizer input is capped to (≈6k tokens). Read by the patched plugin (see Memory section); prevents unbounded summarizer prefills from saturating the memory guard |
| `OPENCODE_MEM_EXCLUDE_DIRS` | unset | Colon-separated dir prefixes where opencode-mem never captures/recalls (read by `patch-opencode-mem-exclude.mjs`). Set sensitive client-repo roots via `ai.env` |
| `SMART_CODING_EXCLUDE_PATTERNS` | unset | Colon-separated extra directory globs kept out of the RAG index, appended to what ProjectDetector emits (read by `patch-smart-coding-excludes.mjs`). Each entry must be exactly `**/<dirname>/**` — file-level globs silently do nothing (see RAG excludes below) |
| `SMART_CODING_EXCLUDE_DEFAULTS` | unset (`true`) | Set `false` to drop the patch's built-in Python virtualenv / tool-cache excludes |
| `OPENCODE_LINT_ENABLED` | `true` | Master on/off for the post-edit-check plugin (ESLint + tsc + Prettier on edit) |
| `OPENCODE_LINT_CHECKS` | `eslint,tsc,prettier` | Which post-edit checks to run (comma-separated subset) |
| `OPENCODE_LINT_MAX_RETRIES` | `3` | Consecutive blocking throws per file before post-edit-check falls back to warn-only (doom-loop guard) |
| `OPENCODE_LINT_EXTENSIONS` | `.ts,.tsx,.js,.jsx,.mjs,.cjs` | File extensions the post-edit-check hook acts on |

The real `ai.env` is gitignored. `ai.env.example` holds commented placeholders for all of the above.

## Dependencies

- `omlx` — local inference server. The Homebrew formula (`brew tap jundot/omlx … && brew install omlx`) currently fails because its sandboxed build can't see `cargo` to compile `rpds-py`; build from source into a venv with `uv` instead:
  ```bash
  git clone https://github.com/jundot/omlx ~/.omlx/src
  uv venv ~/.omlx/venv --python 3.12
  VIRTUAL_ENV=~/.omlx/venv uv pip install -e ~/.omlx/src
  ```
  **Two builds are installed side by side** (see the `--muse` section). The pair above is pinned at `9aa73b1` / `omlx 0.4.2rc1` (mlx 0.31.2, transformers 5.10.2) and serves `ai` / `-l` / `-g`. The `--muse` profile needs a second pair, because a second venv alone would not isolate anything — `~/.omlx/venv` is an *editable* install of `~/.omlx/src`, so pulling that checkout would change the pinned build too:
  ```bash
  git clone https://github.com/jundot/omlx ~/.omlx/src-next   # origin/main
  uv venv ~/.omlx/venv-next --python 3.12
  VIRTUAL_ENV=~/.omlx/venv-next uv pip install -e ~/.omlx/src-next
  ```
  That yields `omlx 0.5.8.dev3` (mlx 0.32.0, transformers 5.12.1). **Never `git pull` `~/.omlx/src`** — it would silently upgrade the working profiles and destroy the rollback path. To refresh the Muse build, pull `~/.omlx/src-next` and re-run its `uv pip install -e`.
- `uv` — used to build/run the oMLX venvs
- `opencode` — frontend, sst/opencode (`brew install sst/tap/opencode`)
- `node` — required by the `opencode-mem` memory plugin (auto-installed by opencode from the `"plugin"` array). On launch `ai.sh` also re-applies `scripts/patch-opencode-mem-cap.mjs` to cap the plugin's summarizer input (idempotent; see the Memory section)
- `smart-coding-mcp` — for RAG, installed as a **private repo-owned copy** so we can patch it without mutating a shared global: `npm install --prefix ~/.smart-coding-omlx smart-coding-mcp`. `opencode.json` launches it from there. Its in-process Xenova embedder is rerouted to oMLX (`bge-m3`) by `scripts/patch-smart-coding-omlx.mjs`, which `ai.sh` re-applies on every launch (idempotent; survives `npm update` of the copy).
  - **RAG excludes — `scripts/patch-smart-coding-excludes.mjs`** (also re-applied every launch). smart-coding-mcp derives its final exclude list from `ProjectDetector` *alone*: `lib/config.js` sets `excludePatterns = [...getSmartIgnorePatterns(), ...userConfig]`, discarding its own 200-entry `DEFAULT_CONFIG.excludePatterns`, and in `--workspace` mode the **package's `config.json` is never read** (it loads `config.json` from the *workspace* root) — so editing the package config fixes nothing. The detector only emits a language's ignore patterns when it *detects* that language, yet `py` is unconditionally in `fileExtensions`. Net effect: a JavaScript repo containing a stray Python virtualenv gets 501 JS-only patterns, none matching `venv`/`site-packages`, and indexes the entire virtualenv as first-party source. Measured on one client repo: **4,348 of 5,115 discovered files and 133,011 of 140,703 chunks (94.5%) came from `.venv`**, producing a 750 MB `embeddings.db` and pinning oMLX above 100% CPU for hours — with **no LLM loaded**, since the embedder issues one HTTP request per chunk (~12/s). The patch adds the `SMART_CODING_EXCLUDE_PATTERNS` / `SMART_CODING_EXCLUDE_DEFAULTS` overrides upstream lacks, applied at the end of `loadConfig()` so they win over both sources; the built-in virtualenv set needs no configuration.
  - **Patterns are not glob-matched.** `features/index-codebase.js#discoverFiles` reduces each pattern to a bare directory name via `pattern.match(/\*\*\/([^/*]+)\/?\*?\*?$/)` and feeds the set to `fdir().exclude(d => set.has(d))` — an exact basename match at any depth. A pattern therefore only works as literally `**/<name>/**` with no wildcard inside `<name>`; `**/*.egg-info/**` extracts nothing and is silently inert (which is why it is deliberately absent from the built-in list), and file-level globs like `**/*.min.js` can never work.
  - **Changing excludes does not shrink an existing index.** Already-stored chunks persist in `.smart-coding-cache/embeddings.db`; delete that directory (with opencode closed, so nothing holds the SQLite WAL) to reclaim the space and re-index clean.
- **Models** live under `~/.omlx/models/` as MLX-format subdirectories. The weights are exposed by symlinking the HF cache snapshot to `~/.omlx/models/<namespace>/<name>` (so the served two-level id matches `opencode.json` — e.g. `mlx-community/Qwen3.6-35B-A3B-6bit`); `bge-m3` (embeddings) is `mlx-community/bge-m3-mlx-fp16` downloaded into `~/.omlx/models/bge-m3`. **Auto-download**: on launch `ai.sh`'s `_ensure_model` checks the selected model is present (a `*.safetensors` under its dir) and, if not, runs `hf download <id>` (using the oMLX venv's `hf`/`huggingface-cli`) then symlinks the resulting snapshot into place — so `ai` (6-bit default, ~27.5 GB), `ai -l` (oQ6-mtp, ~30 GB), `ai -g` (Gemma 4 12B QAT+OptiQ, 9 GB) and `ai --muse` (Muse Glimmer oQ4e, 20.3 GB) fetch their weights on first use instead of failing lazily. Idempotent once the weights exist. The `hf` binary is taken from the *selected profile's* venv, so `--muse` downloads with the newer build's client.
- **Per-model oMLX settings** live in `~/.omlx/model_settings.json` (oMLX's own store, base path `~/.omlx`), **not** in this repo. On launch `ai.sh` runs `scripts/patch-omlx-mtp.mjs` to merge in `mtp_enabled: true` for the oQ6-mtp (`-l`) build and `enable_thinking: false` for Gemma 4 (`-g`) — settings oMLX reads at **model load**, so a change needs a server restart (`ai -k`; the model-switch restart covers the usual case). Each entry is written under **both** the two-level model id and its bare directory-leaf name, because oMLX resolves requests to the leaf and keys settings by that (see the `-g` section — the two-level-only key was silently never consulted). The patch is idempotent and non-destructive: it only writes when a value differs and preserves every other model/key (e.g. anything set via the oMLX admin panel). Schema is `{"version":1,"models":{<id>:{…}}}`; oMLX's `ModelSettings.from_dict` filters to known fields and defaults the rest, so the partial entries the script writes are valid. Override the file path with `OMLX_BASE_DIR` (default `~/.omlx`).

## Server Tuning

oMLX launches with explicit flags (see the `OMLX_*` Configuration vars):

- `--paged-ssd-cache-dir ~/.omlx/cache` — **the headline feature.** Block-based KV cache (vLLM-style, prefix sharing + copy-on-write) with a cold SSD tier; recurring prefixes (system prompt, shared codebase context) are restored from disk on a cache hit — even across a server restart — instead of recomputed. Measured locally: cold prefill ~2.3s → warm ~0.6s on a shared prefix.
- `--paged-ssd-cache-max-size` — disk cap for the SSD tier; oMLX evicts LRU within it. **Split per profile since the `--muse` work: 15 GB for `ai`/`-l`/`-g` in `~/.omlx/cache`, 25 GB for `--muse` in `~/.omlx/cache-next`** — the two oMLX builds disagree on the cache format and both prune oldest-first, so one shared directory would make them evict each other. The budgets sum to the 40 GB the single cache used before. Without it oMLX sizes the cache off free disk space and will grow until the disk is nearly full. **Caveat: this cap only governs oMLX's *live* index.** Blocks orphaned by a prior run or a model/quant switch (each quant writes its own KV blocks) fall out of the index and oMLX's LRU never revisits them, so the on-disk footprint drifts far past the cap — observed at **122 GB against a 40 GB cap** (~19 days of accumulation), filling the disk to 99%. `ai.sh` compensates: `_prune_cache` (in `_start_server`) deletes cache blocks oldest-first (mtime = LRU, matching oMLX's intent) down to `OMLX_CACHE_PRUNE_GB` on every server (re)start. It runs only with the server down, so nothing holds the blocks live; blocks are content-addressed, so a later lookup for a pruned one is just a cache miss → recompute (the safe failure mode).
- `--hot-cache-max-size 8GB` — in-RAM hot KV tier (oMLX default is 0/disabled; must be set explicitly). Bigger tier = more in-memory hits before spilling to SSD — but model (~27.5 GB for the 6-bit default, ~30 GB for oQ6-mtp under `-l`) + tier must stay under the memory guard's **soft threshold (85% of the guard = 40.8 GB at 48)**; at 12 GB the steady state sat above it and the enforcer evicted models mid-request (aborted completions = the agent "choking").
- `--memory-guard-gb 48` — hard ceiling oMLX won't exceed, leaving ~16 GB for macOS/apps on a 64 GB machine. Replaces the old `MLX_CACHE_LIMIT`. Raise on 128 GB configs. Eviction starts at the 85% soft threshold, not the ceiling.
- `--max-concurrent-requests 2` — continuous batching. One slot for the interactive coding turn, one so the opencode-mem summarizer can overlap it instead of serializing. Kept at 2 (not higher) because each concurrent prefill adds transient working memory against the guard's soft threshold; embeddings run on the separate bge-m3 engine and don't compete for these slots.

oMLX auto-tunes the paged-cache block size (e.g. 2048 tokens for the Qwen hybrid model) and reads the model's native context (Qwen3.6 reports 262 144).

**Context window**: opencode advertises **65,536 tokens context / 8,192 output** for the default `mlx` flat-6bit Qwen (`opencode.json`) — conservative vs the native 256 k window. The binding constraint is *not* KV-cache size: this model has only **2 KV heads** (40 layers, head_dim 256), so KV costs ~**80 KB/token** — just ~4 GB at 49 k, ~5.4 GB at 65 k. What actually hits the wall is the **prefill transient** — processing a full-window prompt in one shot spikes activation memory toward Apple's Metal working-set cap (51.8 GB on this 64 GB machine, since `iogpu.wired_limit_mb` is unset); past it oMLX force-kills the prefill (`Memory limit exceeded during prefill`) and the agent "chokes." The flat-6bit default (~27.5 GB resident) has been empirically safe at 65 k. The **`-l` oQ6-mtp build is ~30 GB resident and MTP attaches a draft head with its own verify buffers**, leaving less prefill headroom — so it's capped lower at **49 k** (the +2.5 GB resident is partly offset by how cheap KV is). To push either higher, first raise the Metal cap — `sudo sysctl iogpu.wired_limit_mb=57344` (56 GB) — then bump the `opencode.json` `limit.context`. These figures are calculated estimates; the first real full-window turn is the empirical check that it never chokes.

## Key Details

- Server port: **10081** (OpenAI `/v1`, Anthropic `/v1/messages`, embeddings `/v1/embeddings`, rerank `/v1/rerank`); oMLX admin/chat UI at `/admin`
- Logs: `$AI_LOG_DIR/omlx-server-<timestamp>.log` (ai.sh redirect); oMLX also writes `~/.omlx/logs/server.log`
- State file: `$AI_STATE_DIR/omlx-model` (two lines: model id, then the oMLX binary serving it — a change in either forces a server restart), PID file: `$AI_STATE_DIR/omlx-server.pid`
- Startup timeout: 120 seconds (oMLX binds in ~1–3s; first chat request lazily loads the ~30 GB model)
- In tmux: auto-opens split pane tailing server log
- The `logs/` directory is auto-pruned: `*.log` files older than 14 days are deleted at server start
- opencode config lives at `opencode.json` in this repo, symlinked from `~/.config/opencode/opencode.json`; `opencode-mem.jsonc` is symlinked the same way
- RAG: private smart-coding-mcp (`~/.smart-coding-omlx`), patched to embed via oMLX `bge-m3` (1024-dim, Metal) instead of in-process Xenova; auto-indexes on opencode connect. Switching the embedding model invalidates a workspace's `.smart-coding-cache` (dims changed) — already-indexed projects need a one-time `rm -rf .smart-coding-cache` (or the `c_clear_cache` tool) to re-index; new projects are unaffected.
- Memory: `opencode-mem` plugin — SQLite at `~/.opencode-mem/data`, `bge-m3` embeddings + summarizer both on the local oMLX server; web UI at `http://127.0.0.1:4747`
