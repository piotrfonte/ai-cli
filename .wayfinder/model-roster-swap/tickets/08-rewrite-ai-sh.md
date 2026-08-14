---
id: W8
title: Rewrite ai.sh — profiles, _ensure_model, disk budget, patch scripts
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: [W1, W5, W6, W7, W13]
---

## Question

Make `ai.sh` serve exactly the three models, and nothing else.

### Profiles

- bare `ai` → `lmstudio-community/GLM-4.7-Flash-MLX-6bit`
- `--muse` → `mlx-community/Muse-Glimmer-30B-4bit`
- `--bonsai` → `prism-ml/Ternary-Bonsai-27B-mlx-2bit`

Delete `_model_qwen`, `_model_lite`, `_model_gemma`, `_model_macaw` and their flags.
`-l`, `--lite`, `-g`, `--gemma`, `--macaw` become **hard errors naming the
replacement** — never silent remaps. A stale `ai -l` in shell history must fail
loudly rather than quietly serve a different model.

### `_ensure_model`

Drop the `hf download` path entirely. The new behaviour:

1. If the weights are present in LM Studio's store, create the
   `~/.omlx/models/<org>/<repo>` symlink (idempotent) and continue.
2. If not, **fail** with the exact repo id and an instruction to fetch it in LM
   Studio.

Never write a second copy. Duplicate weights are the specific failure this design
exists to prevent, and the disk is 94% full.

Use the layout W1 proved. Do not repoint `OMLX_MODEL_DIR` — that strands `bge-m3`.
(W1 correction: GGUF exposure is **not** a reason. oMLX skips any HF-cache entry
without a `model*.safetensors` file. The `bge-m3` argument stands on its own.)

W1 adds two steps to the check:

- Reject a partial download. A `downloading_*.part` file in the store means LM Studio
  is still fetching, and the model must fail by name exactly as an absent one does.
- Old dangling symlinks are harmless — oMLX skips them in silence — so removing the
  four departed links is tidiness, not correctness.

### Decide: `hf_cache_enabled`

W1 found that oMLX scans `~/.cache/huggingface/hub` **in addition to** `--model-dir`,
because `~/.omlx/settings.json` carries `huggingface.hf_cache_enabled: true`. Any MLX
model the user pulls into that cache therefore appears in `/v1/models` on its own.
That collides with the destination — "three models and no others". `--model-dir` is
read first, so the symlinked copies win the duplicate tie-break, and the roster is
correct today. Decide whether `ai.sh` should pin `hf_cache_enabled: false` to make
the roster exact, or leave discovery permissive and let the tie-break carry it.

### Disk budget

Cut `OMLX_SSD_CACHE_MAX` and the derived `OMLX_CACHE_PRUNE_GB` to ~25 GB. Update
`ai.env.example` to match.

**W4 correction — the disk numbers moved, and pruning is weaker than assumed.**
`~/.omlx/cache` is **empty** now: W4 deleted all 107 blocks before the upgrade. That
freed **0 usable bytes**. Free disk stays at **14 GiB, 99% full**, because seven APFS
Time Machine local snapshots pin the deleted space. The space is purgeable, so macOS
releases it under pressure, but `_prune_cache` cannot return disk on demand on this
box. Keep the 25 GB cap — it still bounds growth — but do not present pruning as a way
to free space, and do not size anything on the assumption that it does.

W1 also found `~/.omlx/settings.json` carries `cache.ssd_cache_dir: ~/.omlx/cache-next`,
an empty directory, while the 15 GB sits in `~/.omlx/cache`. The `--paged-ssd-cache-dir`
flag overrides it, so `ai.sh` is unaffected, but the persisted setting disagrees with
the launcher and will confuse the next person who reads it.

### Patch scripts

- `scripts/patch-omlx-mtp.mjs` — strip the `DESIRED` entries for the departed models.
  Keep the both-spellings mechanism: an entry keyed only by the two-level id is
  **never consulted**, because oMLX resolves to the directory leaf. Unit-test it
  against a throwaway path: fresh create, idempotent re-run, pre-existing key
  preserved, corrupt file recovered.
- `OPENCODE_MEM_MODEL` must resolve to the new session model, so the opencode-mem
  summarizer reuses the loaded model instead of pulling a second one into memory.

### Also update

`_resolve_runtime` — every profile now shares one venv and one cache directory again.
Keep the mechanism (`OMLX_BIN` overrides still work) but remove the per-profile
divergence the second build needed.

### From W4 — two more things this ticket now owns

**The state file's binary line no longer detects anything.**
`$AI_STATE_DIR/omlx-model` records the oMLX binary *path* on line 2, and a change there
forces a restart. W4 upgraded **in place**, so the path is `~/.omlx/venv/bin/omlx`
before and after — the line cannot see a 2190-commit jump. It was added to separate two
concurrent builds, and this map removes the second build. Either drop the line or record
something that moves, such as the `omlx` version or `git -C ~/.omlx/src rev-parse HEAD`.
Nothing breaks today, because every profile change also changes the model line.

**`hf_cache_enabled` leaks more than models.** On the upgraded build `/v1/models`
answers with `MarkItDown` beside the three models and `bge-m3`. It arrives with the
upgrade's `markitdown` dependency, not from `model_discovery.py`. This costs nothing —
`opencode.json` declares its models explicitly — but weigh it in the
`hf_cache_enabled` decision above, since "three models and no others" is not what
`/v1/models` reports either way.

### Validate

`bash -n ai.sh`, then a real launch of each profile.

## Resolution

**Done. All three profiles launch, link their weights, serve and answer.** `ai.sh`
now knows exactly three models, downloads nothing, and fails loudly by repo id when
a model is absent.

### What the launcher does now

| Command | Model | Label |
|---|---|---|
| `ai` | `lmstudio-community/GLM-4.7-Flash-MLX-6bit` | GLM 4.7 Flash 6-bit |
| `ai --bonsai` | `prism-ml/Ternary-Bonsai-27B-mlx-2bit` | Ternary Bonsai 27B 2-bit |
| `ai --muse` | `mlx-community/Muse-Glimmer-30B-4bit` | Muse Glimmer 30B 4-bit |

`-l`, `--lite`, `-g`, `--gemma`, `-gemma`, `--macaw` and `-macaw` each exit 1 through
`_retired_flag`, naming the departed model **and** printing the three-model roster.
No flag remaps.

`_model_qwen`, `_model_lite`, `_model_gemma` and `_model_macaw` are gone, and with
them `model_context_limit` and `model_omlx_venv`:

- **`model_context_limit` was never read** — it was assigned in all four profiles and
  used nowhere. `opencode.json` is the one place the window is declared, so a second
  copy could only drift out of agreement with it. Removed rather than re-populated.
- **`model_omlx_venv` collapsed** into one `omlx_venv` (with `OMLX_VENV` /
  `OMLX_SRC_DIR` overrides). `_resolve_runtime` keeps its shape and `OMLX_BIN` still
  wins; only the per-profile divergence the second build needed is gone, including
  `_check_deps`'s `-next` special case.

### `_ensure_model`: a verifier, never a downloader

The whole `hf download` path — downloader discovery, the Xet stdout parsing, the
snapshot fallback — is deleted (~60 lines). The new check, in order:

1. No `*.safetensors` under `~/.cache/huggingface/hub/<org>/<repo>` → **fail**, naming
   the repo id and the exact expected path, and saying this launcher never downloads.
2. A `downloading_*` or `*.part` file there → **fail the same way**. A half-fetched
   model must not load as a truncated one; oMLX would report that as a model error
   rather than a missing download.
3. A **real directory** where the symlink belongs → **fail**. That is the second copy
   this design exists to prevent, so it is reported, never overwritten. (`ln -sfn`
   would have failed here anyway, but with a cryptic message.)
4. Otherwise `ln -sfn` the store path under `--model-dir`. A correct link is silent.

`OMLX_MODEL_DIR` is untouched, so `bge-m3` stays where it is. The store path is
`HF_HUB_CACHE`/`HF_HOME`-aware, which is what made the failure paths testable.

**`_prune_stale_model_links` is new**: it removes symlinks under `--model-dir` whose
target no longer resolves, and reports the count. Scoped to broken links only — a
broken link holds no data. It cleared the five departed links (Macaw, both Qwen
quants, the Jundot build, Gemma) on the first launch. Tidiness, as W1 said, but it
keeps `--model-dir` an honest list.

**It also created the Muse Glimmer link W3 left open**:
`~/.omlx/models/mlx-community/Muse-Glimmer-30B-4bit` → the store. W7 measured that
model through oMLX's own HF-cache scan; now `--model-dir` is authoritative for it too.

### Decision — `hf_cache_enabled` stays **true** (discovery stays permissive)

Do not pin it false. Three grounds, the first decisive:

1. **It cannot deliver what it would be for.** After this ticket, with scanning still
   on, `/v1/models` answers `GLM-4.7-Flash-MLX-6bit`, `Muse-Glimmer-30B-4bit`,
   `Ternary-Bonsai-27B-mlx-2bit`, `bge-m3` and **`MarkItDown`**. MarkItDown arrives
   with the upgrade's `markitdown` dependency, not from model discovery, so pinning
   `hf_cache_enabled: false` would not remove it. "Three models and no others" is a
   statement about **what `ai` can select and what `opencode.json` declares** — it was
   never achievable as a statement about `/v1/models`.
2. **The roster is already exact.** `--model-dir` is read first, so the symlinked copy
   wins the duplicate tie-break (W1), and the store holds only roster models plus a
   GGUF that `_is_hf_cache_mlx_compatible()` skips — verified: the `unsloth/bge-small`
   GGUF in that cache does not appear in `/v1/models`.
3. **The cost is a second patch surface.** `ai.sh` does not write `~/.omlx/settings.json`
   today. Pinning the key means re-asserting it on every launch against a file the
   oMLX admin panel also owns, for no measured benefit — and it would fight the user's
   own oMLX use outside this launcher.

The escape hatch matters too: a model dropped into the HF cache can be probed by hand
without touching `ai.sh`, which is exactly how W12 option D and W14 would work.

### Decision — the state file's line 2 now records something that moves

Kept, not dropped. Line 2 is `<binary path>@<git HEAD of the oMLX source checkout>`,
e.g. `/Users/p/.omlx/venv/bin/omlx@350dc08b`. The venv install is **editable**, so
that commit *is* the code being served, and it is the only cheap signal that survives
an in-place upgrade — which is precisely the case W4 created and the old binary-path
line could not see. An unresolvable HEAD reads `unknown`, which is stable, so a box
without git never restarts spuriously. Verified: two consecutive `ai --muse` runs
report *Server already running*, no restart.

### Also changed

- **`OMLX_SSD_CACHE_MAX` 40GB → 25GB**, with `OMLX_CACHE_PRUNE_GB` still derived from
  it, so the two cannot disagree. `ai.env.example` updated to match, including W4's
  correction: pruning **bounds growth, it does not free disk on demand**, because
  macOS may hold the deleted space in APFS snapshots. `~/.omlx/settings.json` already
  carried `ssd_cache_max_size: 25GB` and `ssd_cache_dir: ~/.omlx/cache`, so the
  persisted-setting disagreement W1 found has resolved itself; the CLI flag governs
  either way. Cache measured at 9.3 GB after this session's launches.
- **`scripts/patch-omlx-mtp.mjs`**: `DESIRED` is now **empty**, and the header says why
  — all three models pass their serve check at their own defaults, and MTP stays off
  even on GLM, which carries the head. The script stays wired into `ai.sh` because it
  is the only place a per-model setting can be asserted, it re-asserts over an
  admin-panel toggle, and it is where W12/W15 would land a measured pin. It does **not**
  delete the departed models' entries: they are inert (oMLX reads only the id it
  resolved to) and the script's contract is to preserve every key it did not write.
- **`opencode-mem.jsonc`**: `memoryModel` pointed at the departed 35B. Under `ai.sh`
  this never bites, because `OPENCODE_MEM_MODEL` (the session's own model) wins — but a
  bare `opencode` gateway session falls back to it and would ask oMLX for a model that
  no longer exists. Repointed at the default profile, with a comment saying it is the
  fallback only. No other ticket owns this file.
- **`scripts/bench-omlx.py`**: `--model` defaulted to a departed Qwen quant; repointed
  at GLM.
- The MCP kill-switch **stays and is unclaimed**, as the map's fog says. The `-l` branch
  became `if (( mcp_free ))` with `mcp_free=0` and a comment: the machinery is one
  assignment from live, and nothing on the new roster asks for it.
- Comments carrying departed-model facts were rewritten, not deleted — the profile
  blocks now record each model's measured numbers, its architecture, and the standing
  warning that **the roster is chosen on speed and memory alone**.

### Validation

- `bash -n ai.sh` — clean. `node --check` on both edited `.mjs` files — clean.
  (`shellcheck` is not installed on this box.)
- **`patch-omlx-mtp.mjs` unit-tested against throwaway paths**: with `DESIRED` empty it
  writes nothing and exits 0 (fresh path, pre-existing file byte-identical after two
  runs, corrupt file tolerated without a crash). Because an empty map cannot exercise
  the merge, the machinery was tested separately through a `sed`-injected copy carrying
  one pin: it wrote **both** spellings (two-level id and directory leaf), preserved an
  unrelated model's entry, and the second run was a no-op.
- **A real launch of each profile**, with a stub `opencode` on `PATH` so the launcher
  runs to completion without a TUI. Each brought the server up in ~1 s, linked or
  verified its weights, and handed `opencode` the right `-m mlx/<id>` and
  `OPENCODE_MEM_MODEL`. Each model then answered a live request:

  | Profile | `finish_reason` | `content` | reasoning | model load |
  |---|---|---|---|---|
  | `ai` | `stop` | `ROSTER OK` | 1064 chars | 5.2 s |
  | `ai --bonsai` | `stop` | `ROSTER OK` | 521 chars | 2.7 s |
  | `ai --muse` | `stop` | `ROSTER OK` | 244 chars | 4.6 s |

- **Failure paths**, driven with a temporary store and model dir: weights absent →
  fails by repo id; `downloading_*.part` present → fails as still downloading; a real
  directory at the link path → fails as a second copy. All exit 1 before any server
  starts.
- **Flags**: `-h` renders; `-l` / `--gemma` / `--macaw` exit 1 with the roster;
  `--muse --bonsai` is a conflict error; `--qwen` is unknown; `-k` stops the server and
  frees the port. A repeat launch of the same profile does not restart the server.

### For W9 and W11

- `opencode.json` was **not touched** — it is W9's, and it already carries uncommitted
  `lmstudio` provider edits from an earlier session.
- `ai.env.example` is **done** for the parts W8 owns (cache budget, the new
  `OMLX_VENV` / `OMLX_SRC_DIR` / `HF_HUB_CACHE` entries, the advisor heading). W11
  should re-read rather than rewrite it.
- **`AGENTS.md` is stale and no ticket owned it.** It still describes Qwen, `-l` and
  auto-download in its quick start and architecture table. Added to W11's scope.
- Two new environment variables for CLAUDE.md's configuration table: **`OMLX_VENV`**
  (default `~/.omlx/venv`) and **`OMLX_SRC_DIR`** (default `~/.omlx/src`, and the
  source of the state file's build fingerprint). `HF_HUB_CACHE` is now read by
  `ai.sh` too, as the store location.
- The state file's line 2 changed format; CLAUDE.md's "State file" line must say
  *binary path plus the source checkout's commit*, not *the oMLX binary*.
