---
id: W4
title: Upgrade the oMLX stack in place
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: [W2]
---

## Question

Move `~/.omlx/src` and `~/.omlx/venv` to the target W2 identified — **one build**,
with `mlx`, `mlx-lm`, `mlx-vlm` and `omlx` all upgraded.

### Decided while charting

- Upgrade **in place**. No second checkout, no second venv. The two-build split from
  commit `372570e` existed only to protect the working Qwen profiles, and those
  profiles leave with this map.
- Rollback is real because the checkout is git.

### Steps

1. Record the current state first: `git -C ~/.omlx/src rev-parse HEAD`, plus the
   installed `omlx`, `mlx`, `mlx-lm` and `mlx-vlm` versions. Write them into the
   resolution — this is the rollback recipe.
2. Stop the server (`ai -k`) so nothing holds the venv or the cache blocks.
3. Pull `~/.omlx/src` to the target, then reinstall:
   `VIRTUAL_ENV=~/.omlx/venv uv pip install -e ~/.omlx/src`.
4. Confirm `omlx serve` still accepts every flag `ai.sh` passes.
5. If W2 found the KV cache format version changed, prune `~/.omlx/cache` (15 GB)
   rather than leaving dead blocks against a 94%-full disk.

### Acceptance

The server starts, binds port 10081, and `/v1/models` answers. Model serving itself
is proven per model in W5, W6 and W7 — not here.

### Note

`ai.sh` records the serving binary as the second line of `$AI_STATE_DIR/omlx-model`,
and a change there forces a restart. That is correct behaviour after this upgrade,
not a bug.

### What W2 settled — read this before running step 3

**Target: tag `v0.5.8.dev3` = commit `350dc08b`.** Not `origin/main`, which is one
commit further and only adds `ddgs` for a chat web-search tool this repo never uses.

**Step 1's rollback recipe is already written**, and it has a trap. The pinned
`pyproject.toml` uses *floors* — `mlx>=0.31.2`, `transformers>=5.0.0` — so simply
reinstalling the old checkout leaves the new `mlx` and `transformers` in place. Roll
back with explicit pins:

```bash
git -C ~/.omlx/src checkout 9aa73b19
VIRTUAL_ENV=~/.omlx/venv uv pip install -e ~/.omlx/src \
  "mlx==0.31.2" "mlx-metal==0.31.2" "transformers==5.10.2"
```

State to restore: `omlx 0.4.2rc1`, `mlx 0.31.2`, `mlx-metal 0.31.2`, `mlx-lm 0.31.3`
(`bdb77dae`), `mlx-vlm 0.6.1` (`526c210b`), `transformers 5.10.2`, Python 3.12.13,
checkout `9aa73b19` clean.

**Do not set `OMLX_WITH_CUSTOM_KERNEL`.** The target's `[build-system]` lists
`cmake>=3.27` and `nanobind==2.13.0`, and **cmake is not installed on this box** — but
`setup.py` only adds `ext_modules` when that variable is set or `--with-custom-kernel`
is passed. A plain install compiles nothing. Build isolation will still fetch cmake,
nanobind and a second `mlx` wheel into a throwaway env; `--no-build-isolation` is not
an option because the venv has no setuptools, wheel or pip.

**Step 4 is answered in advance**: all six flags this repo passes are still declared in
`omlx/cli.py` at the target. Confirm at runtime anyway, but expect no change.

**Step 5's premise is wrong, and the conclusion still holds.** The cache format did
**not** change — `_CACHE_FORMAT_VERSION` stays `"3"` at both refs and the readable set
widens, so the existing blocks are safe. Prune anyway, and prune **first**: free disk
is down to **13 GiB at 99% full** and `~/.omlx/cache` holds 15 GB. Blocks are
content-addressed, so a pruned block is a cache miss and a recompute.

## Resolution

**Done. The stack runs at `v0.5.8.dev3` and the server answers.** Every version W2
predicted is the version installed, nothing compiled, and no flag changed. The upgrade
took one `git checkout` and one `uv pip install`.

### 1. Rollback recipe — the state before the change

Recorded from the live venv, so this supersedes W2's from-source estimate. The
checkout was clean at the pin.

| | Before (rollback target) | After (now installed) |
|---|---|---|
| `~/.omlx/src` HEAD | `9aa73b19` clean | `350dc08b` = tag `v0.5.8.dev3`, detached |
| `omlx` | 0.4.2rc1 | **0.5.8.dev3** |
| `mlx` | 0.31.2 | **0.32.0** |
| `mlx-metal` | 0.31.2 | **0.32.0** |
| `mlx-lm` | 0.31.3 git `bdb77dae` | 0.31.3 git **`ab1806e8`** |
| `mlx-vlm` | 0.6.1 git `526c210b` | **0.6.3** git **`78b96eb5`** |
| `transformers` | 5.10.2 | **5.12.1** |
| `huggingface-hub` | 1.18.0 | 1.27.0 |
| `dflash-mlx` | 0.1.9 (bstnxbt `b7f192b6`) | **0.1.10+omlx.5** (jundot `884b5dc7`) |
| Python | 3.12.13 | 3.12.13 (unchanged) |

To roll back, run W2's recipe exactly — the explicit pins are not optional, because the
old `pyproject.toml` floors accept `mlx 0.32.0` and `transformers 5.12.1`:

```bash
git -C ~/.omlx/src checkout 9aa73b19
VIRTUAL_ENV=~/.omlx/venv uv pip install -e ~/.omlx/src \
  "mlx==0.31.2" "mlx-metal==0.31.2" "transformers==5.10.2"
```

**One correction to W2.** W2 lists `dflash-mlx` and `markitdown` as new dependencies.
Both are already installed at the pin; the upgrade only moves them, and `dflash-mlx`
changes fork. The delta is small: **12 packages installed, 11 removed**. `cohere-melody`
0.13.0 is the only genuinely new package. `openai-harmony`, `mistral-common` and
`tabulate` are present at the pin already.

### 2. The install compiles nothing, as W2 promised

`OMLX_WITH_CUSTOM_KERNEL` stayed unset and `cmake` is still absent from this box. The
install resolved 107 packages in 1.18 s and built only `omlx` itself. Build isolation
cost far less than W2 budgeted, because `uv` serves the transient env from its cache.

### 3. All six flags accepted, statically and at runtime

`--model-dir`, `--port`, `--paged-ssd-cache-dir`, `--paged-ssd-cache-max-size`,
`--hot-cache-max-size`, `--memory-guard-gb` and `--max-concurrent-requests` are each
declared once in `omlx/cli.py` at the target. The acceptance run passes the exact set
`ai.sh:435-443` passes, with the current default values. The server accepts all of them.

### 4. Acceptance met

The server binds port 10081 and `/v1/models` answers **HTTP 200 in 3 ms**. It serves:

```
GLM-4.7-Flash-MLX-6bit
Muse-Glimmer-30B-4bit
Ternary-Bonsai-27B-mlx-2bit
bge-m3
MarkItDown
```

The test server is stopped again, and the port is free. No model was loaded — serving
is W5, W6 and W7's job, not this ticket's.

The upgrade delivers what it was bought for. The installed tree carries `muse_glimmer`
in `VLM_MODEL_TYPES` (`model_discovery.py:70`), `MuseGlimmerForConditionalGeneration`
in the architecture list (`:164`), and the vendored compat patch applied at load
(`utils/model_loading.py:472`). None of these exist at the pin.

### 5. Four findings for later tickets

**a. Pruning the KV cache freed 15 GB of blocks and 0 bytes of usable disk.** All 107
blocks are deleted and `~/.omlx/cache` is 0 B, but `df` still reports **14 GiB free at
99%**. Seven APFS **Time Machine local snapshots** from the same day pin the freed
space. The space is purgeable — macOS evicts local snapshots under disk pressure — so
it is a reserve, not a loss. **W8 must not assume a prune returns disk immediately.**
Deleting the snapshots is the user's call and is out of this map's scope.

**b. The state file cannot detect an in-place upgrade.** `$AI_STATE_DIR/omlx-model`
records the binary *path* on its second line, and an in-place upgrade does not change
the path (`~/.omlx/venv/bin/omlx` before and after). The ticket's Note expects a forced
restart from this; the restart happens only because the *model* line differs. This is
harmless for the roster swap, where every profile changes model anyway. W8 should know
that the binary line no longer detects anything, now that one build serves all three.

**c. Muse Glimmer already serves without an oMLX symlink.** It appears in `/v1/models`
from the HF-cache scan alone (`hf_cache_enabled`), so **W7 does not have to wait for
W8's symlink**. The symlink still matters: the log shows oMLX resolving duplicate ids
for GLM and Bonsai and keeping the `~/.omlx/models` copy, which is the tie-break W1
described.

**d. `MarkItDown` is a new entry in `/v1/models`.** It arrives with the upgrade's
`markitdown` document-conversion dependency and is not in `model_discovery.py`. It is
cosmetic here, because `opencode.json` declares its models explicitly.

### 6. One pre-existing warning, unchanged by the upgrade

`process_memory_enforcer` warns that Apple's Metal cap (51.8 GB) sits below oMLX's
static ceiling (62.0 GB), because `iogpu.wired_limit_mb` is unset. This matches the
prefill-transient constraint `CLAUDE.md` already records. It is not new.
