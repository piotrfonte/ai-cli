# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Bash tool (`ai.sh`) that launches a local [oMLX](https://github.com/jundot/omlx) inference server and connects [opencode](https://opencode.ai) (the sst/opencode build) to it. The local model is Qwen 3.6 35B-A3B in a flat MLX **6-bit** quant by default (or, with `-light`, the same model in oMLX's native **oQ6** quant with MTP speculative decode; or, with `-heavy`, a Claude-Opus-distilled reasoning model: Qwen3.5-27B at 6-bit). oMLX is a native Apple-Silicon server whose two-tier KV cache (hot RAM + cold SSD) restores recurring prompt prefixes from disk instead of recomputing them, collapsing agentic time-to-first-token from ~30s to ~1s, and it serves the LLM **and** the embedding model (bge-m3) from one process with continuous batching. opencode has persistent cross-session memory via the `opencode-mem` plugin (local SQLite; embeddings + summarizer run on oMLX — see the Memory section). With `-ooz`, it instead opens an SSH tunnel to a remote OpenAI-compatible endpoint. Designed for Apple Silicon Macs (M4 Max with 64GB RAM assumed).

## Usage

```bash
bash ai.sh              # Qwen 3.6 35B-A3B 6-bit (local oMLX) + opencode
bash ai.sh -light       # Qwen 3.6 35B-A3B oQ6 +MTP (speculative decode) + opencode
bash ai.sh -heavy       # Qwopus: Qwen3.5-27B Opus-distilled reasoning 6-bit + opencode
bash ai.sh --no-hybrid  # Disable the default @advisor cloud-Claude subagent
bash ai.sh -ooz         # SSH tunnel to the OOZ remote endpoint + opencode
bash ai.sh -k           # Kill the local server and OOZ tunnel
bash ai.sh -h           # Show help
bash ai.sh -- --flag    # Pass args through to the frontend
source ai.sh && ai      # Source as a function
```

### Default model — Qwen 3.6 35B-A3B 6-bit

The default `ai` runs **`mlx-community/Qwen3.6-35B-A3B-6bit`** — the A3B MoE (3B active) in a flat MLX **6-bit** quant. ~27.5 GB resident. It's the everyday coder: a broad **65,536** context window (declared in `opencode.json` under provider `mlx`), no per-model oMLX settings to enable, and **auto-downloaded on first use** (see Models below). For the faster oQ6 +MTP build of the same model, use `-light`; for hard reasoning problems, `-heavy`.

### `-light` oQ6 +MTP speculative-decode build

`ai -light` (alias `-l`) runs **`Jundot/Qwen3.6-35B-A3B-oQ6-mtp`** — the same A3B MoE, but in oMLX's native **oQ6** quant (data-driven mixed-precision: bits allocated where layer-sensitivity calibration says they matter) rather than a flat MLX 6-bit, with the model's **MTP** (multi-token prediction) heads preserved. ~30 GB resident. Faster decode than the flat 6-bit default when MTP engages.

**MTP is off by default in oMLX** even when the weights carry MTP heads — it's a per-model setting (`mtp_enabled`), not an `omlx serve` flag. `ai.sh` enables it on launch via `scripts/patch-omlx-mtp.mjs` (see the model_settings.json side-effect below). With it on, oMLX runs a draft+verify speculative-decode loop for **singleton decode when batch rows align** — so a coding turn overlapping the opencode-mem summarizer (the 2nd concurrent slot) falls back to normal decode for that window; the speedup is real but intermittent.

The model is **auto-downloaded on first use** (see Models below) and declared in `opencode.json` under provider `mlx` at a **49,152** context cap (see Context window — KV is cheap for this model, so the cap is set by the prefill transient, not KV size; it sits below the default's 65 k because oQ6-mtp's +2.5 GB resident leaves less prefill headroom).

### `-heavy` Opus-distilled reasoning model

`ai -heavy` runs **`mlx-community/Qwen3.5-27B-Claude-4.6-Opus-Distilled-MLX-6bit`** ("Qwopus") — Qwen3.5-27B fine-tuned on Claude Opus 4.6 reasoning chains, at MLX 6-bit (~20 GB resident). Unlike the A3B default it's a **dense** model and a **reasoning** model: it emits a `<think>…</think>` chain before answering, so it's slower per token and spends tokens thinking — reach for it on hard problems, not as the everyday driver. oMLX is configured (same patch script) with `reasoning_parser: "qwen"` for it, so the `<think>` block is surfaced as a separate `reasoning_content` field instead of leaking raw tags inline into the opencode chat. Its `opencode.json` window is **65,536 context / 16,384 output** — the larger output budget gives the CoT room to finish; the 20 GB resident leaves ample KV headroom for the bigger context.

**opencode-only.** `-heavy` is ignored under `-ooz` (that path uses the remote model). The weights are auto-downloaded on first use.

### Hybrid cloud advisor mode (default on; `--no-hybrid` to disable)

The hybrid cloud advisor is **on by default** on the local opencode path (the default model, `-light`, and `-heavy`). It keeps the local Qwen as the primary coding agent but adds a **read-only, prompt-only cloud-Claude advisor** you summon by hand with `@advisor`. The bulk of the work stays on-box; only the snippet/question you explicitly hand the advisor leaves the machine, for a real cloud-Opus second opinion on a hard architectural call or a correctness/security review. It is **forced off under `-ooz`** (the remote path is kept advisor-free); `--no-hybrid` disables it everywhere. The legacy `-hybrid` flag is still accepted (it now just makes the default explicit, and triggers a warning if combined with `-ooz` where it can't apply). Requires a one-time `opencode auth login` → Anthropic (OAuth, uses your Claude plan — **no API key, no per-token bill**); launches warn if that login is missing.

Three independent privacy controls (defense in depth):

1. **Gating** — the advisor agent (`agents/advisor.md`) is symlinked into `~/.config/opencode/agents/` **only** when the advisor is active; every `--no-hybrid` (or `-ooz`) launch *removes* it, so a no-advisor launch has no agent referencing the `anthropic` provider and therefore **no egress path to the cloud at all**.
2. **Manual** — `opencode.json` sets `permission.task: "ask"`, so even if the local model tries to delegate to the advisor, opencode prompts before anything leaves the box. The advisor is `mode: subagent` (never the primary), invoked via `@advisor`.
3. **Prompt-only** — `advisor.md` denies **every** tool (`read`/`grep`/`glob`/`bash`/`edit`/`write`/…), so the advisor can reason only about the text you hand it — it cannot open files to widen the egress.

The advisor runs on opencode's **built-in `anthropic` provider** (real `api.anthropic.com`), pinned to `anthropic/claude-opus-4-8` — this is **not** the local oMLX endpoint. Every advisor call is recorded by `plugins/advisor-egress-log.js` (see Post-edit checks for the plugin-loading mechanism) to **`logs/advisor-egress.jsonl`** — one append-only JSON line per call (`ts`, `sessionID`, full outbound `prompt`). It's named `.jsonl`, not `.log`, on purpose: `ai.sh` prunes `logs/*.log` older than 14 days and an audit trail must outlive that. `ai.sh` passes the path to the plugin via `ADVISOR_EGRESS_LOG` (derived from `AI_LOG_DIR`); the egress plugin is symlinked in only when the advisor is active and removed otherwise, alongside the agent.

### `-ooz` remote mode

`ai -ooz` skips the local oMLX server. It opens an SSH tunnel (`ssh -f -N -C -L <local>:<remote> -p <port> <user>@<host>`) forwarding a local port to the remote's OpenAI-compatible server, polls the endpoint until healthy, resolves the model id (`OOZ_MODEL` if set, else auto-detected from `/v1/models`), then launches `opencode -m "ooz/<model-id>"`. The remote currently serves `Qwen3.6-35B-A3B-GGUF:Q8_0`, declared in `opencode.json` under provider `ooz` with a 64k/8k limit. SSH connection details (host, user, port) are **delicate** and live in `ai.env` (gitignored), not in the repo. See the OOZ variables in the Configuration table.

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
   - `_start_server` — runs `omlx serve --model-dir … --paged-ssd-cache-dir …` with tuned cache/memory flags (binary resolved via `OMLX_BIN`, default `~/.omlx/venv/bin/omlx`). oMLX discovers models from `--model-dir` subdirectories, so no `--model` is passed; opencode picks the model per request.
   - `_wait_for_server` — polls `/v1/models` with spinner, opens tmux log pane if in tmux
   - `_kill_server` — kills by PID file then port scan (only targets python/mlx/omlx processes — the oMLX process renames itself to `omlx-server`)
   - On a model switch the server is killed/restarted automatically (state file `$AI_STATE_DIR/omlx-model` vs the requested id). But oMLX is multi-model and lazy-loads whatever id a request asks for, so a **lingering opencode from a previous `ai`/`ai -light`/`ai -heavy` run** keeps requesting its old model and oMLX loads it alongside the new one — two ~20-30GB LLMs can't coexist under the memory guard, so it thrashes (evict/reload) and stalls or `507`s requests mid-turn (the agent "chokes"). `_warn_model_conflict` detects this — it reads each running opencode's `-m mlx/<id>` arg and warns if any differs from the model being launched, pointing the user to close that session and `ai -k`. (ai.sh can't fix it automatically — it can't control the other client.)
2. **RAG**: Checks for `smart-coding-mcp` on launch (auto-indexes via opencode MCP config).
3. **OOZ tunnel** (`-ooz` only): `_start_tunnel` opens the SSH forward and polls the local port; `_discover_ooz_model` reads the served model id from `/v1/models`; `_kill_tunnel` kills the listener on the local port (only targets `ssh` processes).
4. **Frontend launch**: After server/endpoint healthy, runs `opencode -m "<provider>/<model-id>"` (`mlx/…` locally, `ooz/…` with `-ooz`; configured via `opencode.json`) in the caller's original `$PWD`.
5. **Hybrid advisor** (on by default on the local path; off under `-ooz` or `--no-hybrid`): symlinks `agents/advisor.md` → `~/.config/opencode/agents/advisor.md` and `plugins/advisor-egress-log.js` → `~/.config/opencode/plugins/`, runs an Anthropic-OAuth preflight warning, and exports `ADVISOR_EGRESS_LOG`. Every non-advisor launch *removes* both symlinks (the airgap guarantee). See the Hybrid cloud advisor mode section above.

### `opencode.json` — OpenCode provider config

Configures two providers: `mlx` (local, port 10081) and `ooz` (remote tunnel, port 8089), both OpenAI-compatible. The `ooz` provider declares `Qwen3.6-35B-A3B-GGUF:Q8_0` (the current remote model); the id passed via `-m` comes from `OOZ_MODEL` or runtime discovery and must match a declared id to pick up its limits. Context limit (64k), output limit (8k), and timeout. Also configures smart-coding-mcp for RAG indexing and enables the `opencode-mem` plugin via the top-level `"plugin"` array. `chrome-devtools` MCP is registered but disabled by default — flip `enabled` to true per-session if browser automation is needed. A third provider, `anthropic` (real cloud Claude), is **not** declared here — it's opencode's built-in and resolves via `opencode auth login`; only the `-hybrid` advisor agent references it. The top-level `permission.task: "ask"` enforces the advisor's manual-only rule (see `-hybrid` mode).

### Memory — `opencode-mem` plugin (`opencode-mem.jsonc`)

Persistent cross-session memory for opencode. Activated by `"plugin": ["opencode-mem"]` in `opencode.json`; configured by `opencode-mem.jsonc` in this repo, symlinked to `~/.config/opencode/opencode-mem.jsonc` (same pattern as `opencode.json`). Fully local:

- **Storage**: SQLite (source of truth) at `~/.opencode-mem/data`; macOS uses Homebrew SQLite via `customSqlitePath`. Inspect with `sqlite3` or the web UI at `http://127.0.0.1:4747`.
- **Embeddings**: `bge-m3` (1024-dim, MLX/Metal) served by **oMLX** via `/v1/embeddings`. Setting `embeddingApiUrl` + `embeddingApiKey` in `opencode-mem.jsonc` switches the plugin off its in-process Xenova path onto the oMLX endpoint. (Switching from the old 768-dim nomic embeddings changes dimensions — if recall misbehaves on an existing store, clear `~/.opencode-mem/data` to force re-embedding.)
- **Auto-retain**: `autoCaptureEnabled` summarizes salient turns after idle. The summarizer is pointed at the **local oMLX server** (`memoryApiUrl: http://127.0.0.1:10081/v1`) — so capture stays on-box. It needs the oMLX server up (always true when launched via `ai.sh`). `autoCaptureMaxIterations` is raised to 8 now that oMLX's continuous batching lets the summarizer overlap coding turns instead of fighting a single decode slot.
  - **Input cap (important)**: the summarizer is a raw OpenAI client to oMLX, so it **bypasses opencode.json's context limit**. Its `buildMarkdownContext` includes the full, uncapped assistant text of a turn — and when captures fall behind, the message slice spans much of the conversation. Left unbounded this produced ~120k-token summarizer prefills whose KV cache saturated the memory guard: interactive coding turns got throttled (a 3.8k-token turn took 340s) and concurrent `bge-m3` embedding loads were rejected with HTTP 507 — the agent appeared to "choke" mid-task. `ai.sh` re-applies `scripts/patch-opencode-mem-cap.mjs` on every launch (idempotent; patches both the config-dir install and the plugin cache) to cap the summarizer input to `OPENCODE_MEM_MAX_CONTEXT_CHARS` chars (default 24000 ≈ 6k tokens), keeping the request-framing head and outcome tail and eliding the middle. This is what makes the `autoCaptureMaxIterations: 8` overlap safe.
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
| `OMLX_BIN` | `~/.omlx/venv/bin/omlx` (else `omlx` on PATH) | oMLX server binary |
| `OMLX_MODEL_DIR` | `~/.omlx/models` | Dir oMLX discovers models from (subdirectories) |
| `OMLX_BASE_DIR` | `~/.omlx` | oMLX base path; `$OMLX_BASE_DIR/model_settings.json` is where `patch-omlx-mtp.mjs` writes MTP/reasoning settings |
| `OMLX_CACHE_DIR` | `~/.omlx/cache` | Paged SSD KV-cache directory |
| `OMLX_HOT_CACHE` | `8GB` | In-RAM hot KV-cache tier size (model + tier must fit under the memory guard's soft threshold) |
| `OMLX_SSD_CACHE_MAX` | `40GB` | Disk cap for the paged SSD cache (unset, oMLX claims nearly all free disk) |
| `OMLX_MEMORY_GUARD_GB` | `48` | Memory ceiling oMLX won't exceed (headroom on 64 GB) |
| `OMLX_MAX_CONCURRENT` | `2` | Max concurrent requests (continuous batching): 1 coding turn + 1 opencode-mem summarizer. Don't set to 1 — memory captures would serialize with coding turns |
| `OPENCODE_MEM_MAX_CONTEXT_CHARS` | `24000` | Char budget the opencode-mem summarizer input is capped to (≈6k tokens). Read by the patched plugin (see Memory section); prevents unbounded summarizer prefills from saturating the memory guard |
| `OPENCODE_LINT_ENABLED` | `true` | Master on/off for the post-edit-check plugin (ESLint + tsc + Prettier on edit) |
| `OPENCODE_LINT_CHECKS` | `eslint,tsc,prettier` | Which post-edit checks to run (comma-separated subset) |
| `OPENCODE_LINT_MAX_RETRIES` | `3` | Consecutive blocking throws per file before post-edit-check falls back to warn-only (doom-loop guard) |
| `OPENCODE_LINT_EXTENSIONS` | `.ts,.tsx,.js,.jsx,.mjs,.cjs` | File extensions the post-edit-check hook acts on |
| `OOZ_SSH_HOST` | — | Remote SSH host for `-ooz` (delicate; set in `ai.env`) |
| `OOZ_SSH_USER` | — | Remote SSH user for `-ooz` (delicate; set in `ai.env`) |
| `OOZ_SSH_PORT` | `22` | Remote SSH port for `-ooz` |
| `OOZ_LOCAL_PORT` | `8089` | Local forwarded port opencode connects to (must match `opencode.json` `ooz` baseURL) |
| `OOZ_REMOTE` | `127.0.0.1:8080` | Remote `host:port` the OpenAI-compatible endpoint listens on |
| `OOZ_MODEL` | auto-detect | Remote model id (must match an id declared in `opencode.json` provider `ooz`) |

The real `ai.env` is gitignored. `ai.env.example` holds commented placeholders for all of the above.

## Dependencies

- `omlx` — local inference server. The Homebrew formula (`brew tap jundot/omlx … && brew install omlx`) currently fails because its sandboxed build can't see `cargo` to compile `rpds-py`; build from source into a venv with `uv` instead:
  ```bash
  git clone https://github.com/jundot/omlx ~/.omlx/src
  uv venv ~/.omlx/venv --python 3.12
  VIRTUAL_ENV=~/.omlx/venv uv pip install -e ~/.omlx/src
  ```
- `uv` — used to build/run the oMLX venv
- `ssh` — required for `-ooz` remote mode
- `opencode` — frontend, sst/opencode (`brew install sst/tap/opencode`)
- `node` — required by the `opencode-mem` memory plugin (auto-installed by opencode from the `"plugin"` array). On launch `ai.sh` also re-applies `scripts/patch-opencode-mem-cap.mjs` to cap the plugin's summarizer input (idempotent; see the Memory section)
- `smart-coding-mcp` — for RAG, installed as a **private repo-owned copy** so we can patch it without mutating a shared global: `npm install --prefix ~/.smart-coding-omlx smart-coding-mcp`. `opencode.json` launches it from there. Its in-process Xenova embedder is rerouted to oMLX (`bge-m3`) by `scripts/patch-smart-coding-omlx.mjs`, which `ai.sh` re-applies on every launch (idempotent; survives `npm update` of the copy).
- **Models** live under `~/.omlx/models/` as MLX-format subdirectories. The weights are exposed by symlinking the HF cache snapshot to `~/.omlx/models/<namespace>/<name>` (so the served two-level id matches `opencode.json` — e.g. `mlx-community/Qwen3.6-35B-A3B-6bit`); `bge-m3` (embeddings) is `mlx-community/bge-m3-mlx-fp16` downloaded into `~/.omlx/models/bge-m3`. **Auto-download**: on launch `ai.sh`'s `_ensure_model` checks the selected model is present (a `*.safetensors` under its dir) and, if not, runs `hf download <id>` (using the oMLX venv's `hf`/`huggingface-cli`) then symlinks the resulting snapshot into place — so `ai` (6-bit default, ~27.5 GB), `ai -light` (oQ6-mtp, ~30 GB), and `ai -heavy` (Qwopus 6-bit, ~20 GB) fetch their weights on first use instead of failing lazily. Idempotent once the weights exist.
- **Per-model oMLX settings** live in `~/.omlx/model_settings.json` (oMLX's own store, base path `~/.omlx`), **not** in this repo. On launch `ai.sh` runs `scripts/patch-omlx-mtp.mjs` to merge in `mtp_enabled: true` for the oQ6-mtp (`-light`) build and `reasoning_parser: "qwen"` for Qwopus — settings oMLX reads at **model load**, so a change needs a server restart (`ai -k`; the model-switch restart covers the usual case). The patch is idempotent and non-destructive: it only writes when a value differs and preserves every other model/key (e.g. anything set via the oMLX admin panel). Schema is `{"version":1,"models":{<id>:{…}}}`; oMLX's `ModelSettings.from_dict` filters to known fields and defaults the rest, so the partial entries the script writes are valid. Override the file path with `OMLX_BASE_DIR` (default `~/.omlx`).

## Server Tuning

oMLX launches with explicit flags (see the `OMLX_*` Configuration vars):

- `--paged-ssd-cache-dir ~/.omlx/cache` — **the headline feature.** Block-based KV cache (vLLM-style, prefix sharing + copy-on-write) with a cold SSD tier; recurring prefixes (system prompt, shared codebase context) are restored from disk on a cache hit — even across a server restart — instead of recomputed. Measured locally: cold prefill ~2.3s → warm ~0.6s on a shared prefix.
- `--paged-ssd-cache-max-size 40GB` — disk cap for the SSD tier; oMLX evicts LRU within it. Without it oMLX sizes the cache off free disk space and will grow until the disk is nearly full.
- `--hot-cache-max-size 8GB` — in-RAM hot KV tier (oMLX default is 0/disabled; must be set explicitly). Bigger tier = more in-memory hits before spilling to SSD — but model (~27.5 GB for the 6-bit default, ~30 GB for oQ6-mtp under `-light`) + tier must stay under the memory guard's **soft threshold (85% of the guard = 40.8 GB at 48)**; at 12 GB the steady state sat above it and the enforcer evicted models mid-request (aborted completions = the agent "choking").
- `--memory-guard-gb 48` — hard ceiling oMLX won't exceed, leaving ~16 GB for macOS/apps on a 64 GB machine. Replaces the old `MLX_CACHE_LIMIT`. Raise on 128 GB configs. Eviction starts at the 85% soft threshold, not the ceiling.
- `--max-concurrent-requests 2` — continuous batching. One slot for the interactive coding turn, one so the opencode-mem summarizer can overlap it instead of serializing. Kept at 2 (not higher) because each concurrent prefill adds transient working memory against the guard's soft threshold; embeddings run on the separate bge-m3 engine and don't compete for these slots.

oMLX auto-tunes the paged-cache block size (e.g. 2048 tokens for the Qwen hybrid model) and reads the model's native context (Qwen3.6 reports 262 144).

**Context window**: opencode advertises **65,536 tokens context / 8,192 output** for the default `mlx` flat-6bit Qwen (`opencode.json`) — conservative vs the native 256 k window. The binding constraint is *not* KV-cache size: this model has only **2 KV heads** (40 layers, head_dim 256), so KV costs ~**80 KB/token** — just ~4 GB at 49 k, ~5.4 GB at 65 k. What actually hits the wall is the **prefill transient** — processing a full-window prompt in one shot spikes activation memory toward Apple's Metal working-set cap (51.8 GB on this 64 GB machine, since `iogpu.wired_limit_mb` is unset); past it oMLX force-kills the prefill (`Memory limit exceeded during prefill`) and the agent "chokes." The flat-6bit default (~27.5 GB resident) has been empirically safe at 65 k. The **`-light` oQ6-mtp build is ~30 GB resident and MTP attaches a draft head with its own verify buffers**, leaving less prefill headroom — so it's capped lower at **49 k** (the +2.5 GB resident is partly offset by how cheap KV is). To push either higher, first raise the Metal cap — `sudo sysctl iogpu.wired_limit_mb=57344` (56 GB) — then bump the `opencode.json` `limit.context`. `-heavy` (Qwen3.5-27B 6-bit, ~20 GB resident) has far more headroom, so it runs at **65 k context / 16 k output** (the larger output budget also gives its `<think>` CoT room to finish). The remote `ooz` provider stays at 64 k (it runs on a different machine, not subject to this Mac's Metal cap). These figures are calculated estimates; the first real full-window turn is the empirical check that it never chokes.

## Key Details

- Server port: **10081** (OpenAI `/v1`, Anthropic `/v1/messages`, embeddings `/v1/embeddings`, rerank `/v1/rerank`); oMLX admin/chat UI at `/admin`
- Logs: `$AI_LOG_DIR/omlx-server-<timestamp>.log` (ai.sh redirect); oMLX also writes `~/.omlx/logs/server.log`
- State file: `$AI_STATE_DIR/omlx-model` (single line: model id), PID file: `$AI_STATE_DIR/omlx-server.pid`
- Startup timeout: 120 seconds (oMLX binds in ~1–3s; first chat request lazily loads the ~30 GB model)
- In tmux: auto-opens split pane tailing server log
- The `logs/` directory is auto-pruned: `*.log` files older than 14 days are deleted at server start
- opencode config lives at `opencode.json` in this repo, symlinked from `~/.config/opencode/opencode.json`; `opencode-mem.jsonc` is symlinked the same way
- RAG: private smart-coding-mcp (`~/.smart-coding-omlx`), patched to embed via oMLX `bge-m3` (1024-dim, Metal) instead of in-process Xenova; auto-indexes on opencode connect. Switching the embedding model invalidates a workspace's `.smart-coding-cache` (dims changed) — already-indexed projects need a one-time `rm -rf .smart-coding-cache` (or the `c_clear_cache` tool) to re-index; new projects are unaffected.
- Memory: `opencode-mem` plugin — SQLite at `~/.opencode-mem/data`, `bge-m3` embeddings + summarizer both on the local oMLX server; web UI at `http://127.0.0.1:4747`
