---
id: W11
title: Rewrite CLAUDE.md and ai.env.example for the new roster
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: [W8, W9, W17, W19]
---

## Question

Make the documentation describe the tool that now exists.

**Blocked deliberately until last — W18.** Two open tickets can still move what this file
must say. [Measure GLM with thinking pinned off](19-glm-thinking-pin.md) can return GLM to
the default, and [Buy prefill headroom for GLM](17-glm-prefill-headroom.md) can change its
declared window. This is a substantial rewrite of a 46 KB file whose value lies in
recording *why*, so it runs once, at the end of the route, rather than twice.

**One of the two is settled — W19.** GLM did **not** retake the default: the pin removed
every runaway and cost 2 solved tasks, so Muse Glimmer stays bare `ai` and the roster pins
nothing. This ticket now waits on [Buy prefill headroom for GLM](17-glm-prefill-headroom.md)
alone, which can still move GLM's declared window off 32,768.

W19 adds material this rewrite must carry, because it is exactly the kind of *why* the file
exists to record:

- The roster pins **nothing**, and that is now a **measured** result rather than a default.
  The old `CLAUDE.md` documents an `enable_thinking: false` pin for a departed Gemma
  profile; the replacement should say the one pin this roster had cause to try was tried
  and reverted, so nobody re-adds it.
- `patch-omlx-mtp.mjs` **never deletes a key**, so emptying `DESIRED` does not clear a live
  setting. The Configuration section describes that file; this trap belongs with it.
- oMLX reports `reasoning_content` **empty** on a run that hits the output cap mid-reason,
  because it splits only at the closing tag. That contradicts the natural reading of the
  existing serve-check advice and should be stated where `finish_reason` is discussed.

**The default changed.** [W18](18-default-after-capability.md) made **Muse Glimmer** the
default and moved GLM to `--glm`, on minutes per solved task (Muse 3.46, GLM 3.83, Bonsai
4.09) rather than on tok/s. The "Add" list below still says the roster rests on speed and
memory with capability untested — that is now false. Cite W14's capability numbers and
W18's metric, and explain why raw speed flattered the model that wasted 79% of its
wall-clock.

`CLAUDE.md` is ~46 KB and heavily model-specific. Roughly half of it documents models
that no longer exist, so this is a substantial rewrite, not a find-and-replace.

### Remove

Every section on Qwen 3.6 35B-A3B (both quants), Gemma 4 12B and Macaw — including
the `-l` MCP-free behaviour, the oQ6/MTP discussion, the Gemma quant comparison table
and thinking-off finding, and the Macaw prefill measurements.

### Keep, because they are still true and hard-won

- The oMLX two-tier KV cache and why the SSD tier needs `_prune_cache` (oMLX's own
  eviction tracks only its live index, so orphaned blocks leaked to 122 GB against a
  40 GB cap).
- The prefill-transient reasoning: the wall is Metal's working-set cap (51.8 GB
  here), not KV size, and `sudo sysctl iogpu.wired_limit_mb` is the lever.
- The `model_settings.json` **directory-leaf** keying rule — an entry under the
  two-level id alone is silently never consulted.
- The measurement rule: isolate prefill with `max_tokens: 1`; never subtract decode
  from the log line, because builds report `tok/s` differently.
- opencode-mem's summarizer input cap, the memory sections, post-edit-check, the
  hybrid advisor, and the RAG exclude machinery.

### Add

- The three profiles with their **measured** numbers from W5, W6 and W7 — prefill at
  ~10k and ~25k, decode, resident, cold load. Measured, not estimated; say which is
  which.
- The model facts already established while charting (MLA and the MTP head on GLM;
  Bonsai's ternary quant, its 3:1 linear/full attention split and its always-loaded
  vision tower; Muse Glimmer's perception encoder).
- **The sharing contract**: LM Studio owns the store at
  `~/.cache/huggingface/hub/<org>/<repo>`, oMLX reaches it by symlink, the user
  downloads by hand, and `ai.sh` never downloads. This is the single most surprising
  thing about the new setup and the easiest to break by accident.
- The Muse Glimmer history, honestly: removed once for prefill, brought back as a
  different artifact, and what it measured this time.
- **The door charge, not "time to first token"** — [W13](13-roster-after-prefill.md)
  measured that the cold prefill is paid once per directory visit, because the paged
  cache hits on a growing conversation's prefix. Each later turn prefills only its
  fresh tokens, plus up to ~2k of block-alignment slack, because `cached_tokens` rounds
  down to a 2048-token block. Document both numbers per profile: the door charge and
  the per-turn cost. The old phrasing conflated them and made Bonsai look ~3× worse
  than it is. The vocabulary is fixed in [CONTEXT.md](../../../CONTEXT.md).
- **A plain statement that capability is untested.** Required by
  [W13](13-roster-after-prefill.md) §3. The roster is chosen on **speed and memory
  alone**; every serve check proves a model *works*, never that it writes good code.
  Bonsai's "95% of FP16 retained" is a vendor claim against its own FP16, not against
  the other two. If [W14](14-capability-comparison.md) has closed by the time this
  ticket runs, cite its results instead — but do not quietly drop the caveat.

### Also update

`ai.env.example` — **already done by [W8](08-rewrite-ai-sh.md)**: the cache budget is
25 GB, the departed models' variables are gone, and `OMLX_VENV`, `OMLX_SRC_DIR` and
`HF_HUB_CACHE` are documented. Re-read it against `ai.sh`; do not rewrite it.

**`AGENTS.md` — added by W8.** No ticket owned this file and it is now wrong: its
quick start still lists `-l` and Qwen, its architecture table still says
`opencode.json` declares the 35B and the oQ6-mtp build, and it still claims models
auto-download through `hf download`. It is short, so this is a rewrite, not a patch.

**Two new environment variables** for the configuration table, both from W8:
`OMLX_VENV` (default `~/.omlx/venv`) and `OMLX_SRC_DIR` (default `~/.omlx/src`).
`HF_HUB_CACHE` is read by `ai.sh` as well, as the location of LM Studio's store.

**The state file changed shape.** Line 2 is no longer the oMLX binary path — it is
that path plus the source checkout's git commit (`…/omlx@350dc08b`). W8 kept the line
because an in-place upgrade never moves the binary path, so the commit is the half
that can force a restart.

### Validate

Re-read the result against `ai.sh` as it now stands. The old doc's value came from
recording *why*, not *what*; keep that standard.

## Resolution

**Done. `CLAUDE.md` and `AGENTS.md` are rewritten, `ai.env.example` is corrected
additively, and every repo validation command passes.** The rewrite also found that
one of this ticket's own instructions was false, and that three source comments
contradicted the code they document.

### 1. The premise "the roster pins nothing" is wrong — it pins a rail

This ticket, the map's constraint 9, and `patch-omlx-mtp.mjs`'s **own header** all say
the roster pins nothing and `DESIRED` is "deliberately empty". Read the file:

```js
const DESIRED = {
  "lmstudio-community/GLM-4.7-Flash-MLX-6bit": { max_context_window: 36864 },
  "prism-ml/Ternary-Bonsai-27B-mlx-2bit": { max_context_window: 69632 },
  "mlx-community/Muse-Glimmer-30B-4bit": { max_context_window: 69632 },
};
```

W12 added those rails and updated the script's *lower* comment block, not its header,
so the file has contradicted itself since. The live `~/.omlx/model_settings.json`
confirms all six entries (both spellings each).

The distinction the docs now draw, because it is the one that matters: **the roster
pins no *behaviour*** — no `enable_thinking`, no `mtp_enabled`, no reasoning cap —
**and one *safety rail* per model**, `max_context_window` = declared context + one
4,096-token block. Writing "pins nothing" would have told a reader the file is empty
when it holds load-bearing entries, and GLM's rail is what turns a five-minute
force-stop into a 1.67 s HTTP 400.

Header corrected in `scripts/patch-omlx-mtp.mjs`.

### 2. The never-deletes trap is not hypothetical — it is live

W19 warned that `patch-omlx-mtp.mjs` never deletes a key. The live file still carries:

```
"Jundot/Qwen3.6-35B-A3B-oQ6-mtp": { "mtp_enabled": true }
"mlx-community/gemma-4-12B-it-qat-OptiQ-4bit": { "enable_thinking": false }
```

plus both leaf spellings — settings for two models this roster removed. They are inert
(oMLX only reads the id it resolved a request to), so nothing is broken and nothing was
deleted here. But the trap is documented against an observed instance rather than a
principle, in both `CLAUDE.md` and `ai.env.example`.

### 3. Three source comments were wrong; all three fixed

Comment-only edits, no behaviour change, `bash -n` and `node --check` re-run after each:

- **`ai.sh`, the GLM fail-safe**: claimed "the `max_context_window` pin in
  `model_settings.json` still reads 65,536 here". It reads **36,864**. The comment also
  did not say which way the degraded overlay and the rail interact — the session
  advertises 24,576 while the rail stays 36,864, which is the safe way round.
- **`ai.sh`, the advisor block**: "enabled by default (default/-l/-m)" named two
  retired flags.
- **`patch-omlx-mtp.mjs` header**: see §1.

### 4. `ai.env.example` was missing four knobs that are actually read

The ticket said W8 finished this file and it needed only a re-read. The re-read found
four variables read by `ai.sh`, its patch scripts or the lint plugin, and documented
nowhere:

| Variable | Read by |
|---|---|
| `OMLX_BASE_DIR` | `ai.sh` (locates `model_settings.json`) |
| `SMART_CODING_OMLX_DIR` | `ai.sh` (the private smart-coding copy) |
| `OPENCODE_MEM_MAX_CONTEXT_CHARS` | `patch-opencode-mem-cap.mjs` |
| `OPENCODE_LINT_ENABLED` / `_CHECKS` / `_MAX_RETRIES` / `_EXTENSIONS` | `plugins/post-edit-check.js` |

Added as commented entries in the existing sections. The file was **not** rewritten, as
instructed. One correction to an existing row: `HF_HUB_CACHE` also honours `HF_HOME`
(`${HF_HUB_CACHE:-${HF_HOME:-~/.cache/huggingface}/hub}`).

### 5. `AGENTS.md` was wrong in every row, plus one row about nothing

Rewritten, not patched, as the ticket expected. Beyond the known staleness (quick start
listing `-l` and Qwen, the auto-download claim, `opencode.json` declaring the 35B), it
listed **`skills/` — 22 custom skills**. That directory does not exist in this repo.
Removed. It now carries the roster with measured numbers, the min-per-solved-task
reasoning, the weight-sharing contract, the two-line state file, and the Bash gap.

### 6. One live config fact, flagged and not touched

`opencode.json`'s top-level `"model"` is an **uncommitted working-tree change** from
`vercel/alibaba/qwen3.8-max` (at `HEAD`) to **`zai/glm-5.2`**, and
`~/.local/share/opencode/auth.json` holds credentials for `anthropic`, `vercel` and
`openrouter` only — **no `zai`**. So a bare `opencode` needs its own
`opencode auth login` before it will run.

Nothing was changed. It affects no profile — `ai.sh` passes `-m mlx/<id>` and a CLI flag
beats the config default — and the gateway default is explicitly **Out of scope** on the
map. `CLAUDE.md` documents the key's *role* (it must never name a local model) and
states the current value and the missing credential.

`ai.sh`'s own comment still says "now a Vercel AI Gateway model", which matches `HEAD`
and not the working tree. Left alone deliberately: correcting a committed comment to
match an uncommitted experiment would be the wrong direction.

### What the rewrite carries

`CLAUDE.md` is a full rewrite. Structure: what this is → usage → the roster → capability
→ door charge vs per-turn prefill → context windows → the weight-sharing contract →
opencode config → per-model settings → speculative decode → validating changes →
architecture → configuration → dependencies → server tuning → key details.

Kept, as the ticket required: the two-tier cache and why `_prune_cache` is load-bearing
(122 GB against a 40 GB cap); the prefill-transient reasoning; the directory-leaf keying
rule; the `max_tokens: 1` measurement rule; opencode-mem's input cap; post-edit-check;
the hybrid advisor; the RAG exclude machinery.

Added: all three profiles' measured prefill/decode/resident/cold-load, in one table,
labelled measured or computed (GLM's 21.8 s door charge is computed from its measured
~590 tok/s); the architecture facts for each model; the sharing contract; Muse Glimmer's
history stated honestly; door charge vs per-turn prefill with the 2048-block rounding;
W19's three additions (nothing pinned *by measurement*, the never-deletes trap, the
empty `reasoning_content` on a runaway).

**Capability is no longer described as untested.** The ticket's fallback clause applies:
W14 closed, so its results are cited — 9/12 vs 6/12 vs 5/12, GLM's 0-of-12 repair
recovery, its 4 runaways, and W18's minutes-per-solved-task metric with the explanation
of why tok/s flatters a model that wastes 79% of its wall-clock. The caveat was not
dropped, it moved: the measurement covers prompts under 4,000 tokens only, and the 6 → 4
swing in W19 sits inside the suite's noise band. Both are stated.

Also documented as a first-class gap: **`post-edit-check` lints JS/TS only, so nothing
in this repo catches a Bash defect** — with W14's 0/9 first-shot on T3 as the evidence.

### Validation

| Check | Result |
|---|---|
| `bash -n ai.sh` | passes |
| `python3 -m json.tool opencode.json` | passes |
| `node --check` on all `scripts/*.mjs` + `plugins/*.js` | passes |
| `node scripts/patch-omlx-mtp.mjs /tmp/ms-test.json` | writes all 6 entries; **re-run prints nothing** (idempotent) |
| Departed-model grep over the three docs | only deliberate mentions remain: the retired-flag errors, the stale-settings trap, and `HEAD`'s gateway model |

Every default in the configuration table was read back off `ai.sh`, not carried over
from the old file.

### Two incidental facts, recorded not acted on

- **The DFlash drafter is still on disk**: `models--meta-models--Muse-Glimmer-30B-assistant`,
  **4.8 GB** in the HF cache, although DFlash is off for every roster model (W15). It is
  not a roster model, so `_ensure_model` and `_prune_stale_model_links` never touch it,
  and the store is managed by hand in LM Studio by design. Deleting it is the user's
  call.
- **The KV cache sits at exactly its 25 GB cap** and the data volume is 94% full
  (60 GiB free), which is `_prune_cache` doing its job rather than a warning.

### Addendum — `AGENTS.md` is untracked by design

It does not appear in `git status` after the rewrite, and it is not a mistake:
`~/.gitignore_global:2` ignores `AGENTS.md` globally, so this repo can never commit it.
W8 created it and this ticket rewrote it, but it lives only on this box. Anyone
reproducing this repo elsewhere gets `CLAUDE.md` and not `AGENTS.md` — which is an
argument for keeping `CLAUDE.md` self-sufficient, as it now is.
