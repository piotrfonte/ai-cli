# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Bash tool (`ai.sh`) that launches a local [oMLX](https://github.com/jundot/omlx) inference server and connects [opencode](https://opencode.ai) (the sst/opencode build) to it. The local model is Qwen 3.6 35B-A3B. oMLX is a native Apple-Silicon server whose two-tier KV cache (hot RAM + cold SSD) restores recurring prompt prefixes from disk instead of recomputing them, collapsing agentic time-to-first-token from ~30s to ~1s, and it serves the LLM **and** the embedding model (bge-m3) from one process with continuous batching. opencode has persistent cross-session memory via the `opencode-mem` plugin (local SQLite; embeddings + summarizer run on oMLX — see the Memory section). With `-ooz`, it instead opens an SSH tunnel to a remote OpenAI-compatible endpoint; with `-cc`, it points Claude Code at the local oMLX Anthropic endpoint. Designed for Apple Silicon Macs (M4 Max with 64GB RAM assumed).

## Usage

```bash
bash ai.sh              # Qwen 3.6 (local oMLX) + opencode
bash ai.sh -ooz         # SSH tunnel to the OOZ remote endpoint + opencode
bash ai.sh -cc          # Claude Code → local oMLX (experimental)
bash ai.sh -k           # Kill the local server and OOZ tunnel
bash ai.sh -h           # Show help
bash ai.sh -- --flag    # Pass args through to the frontend
source ai.sh && ai      # Source as a function
```

### `-cc` Claude Code mode

`ai -cc` ensures the local oMLX server is up, then launches Claude Code with `ANTHROPIC_BASE_URL=http://127.0.0.1:10081`, a dummy `ANTHROPIC_API_KEY`, and `ANTHROPIC_MODEL`/`ANTHROPIC_SMALL_FAST_MODEL` set to the served Qwen id — so Claude Code talks to oMLX's Anthropic-compatible `/v1/messages` while believing it's Anthropic. Experimental: Qwen's tool-call format differs from Anthropic's; oMLX adapts it, but behaviour is less battle-tested than the opencode path.

### `-ooz` remote mode

`ai -ooz` skips the local oMLX server. It opens an SSH tunnel (`ssh -f -N -C -L <local>:<remote> -p <port> <user>@<host>`) forwarding a local port to the remote's OpenAI-compatible server, polls the endpoint until healthy, resolves the model id (`OOZ_MODEL` if set, else auto-detected from `/v1/models`), then launches `opencode -m "ooz/<model-id>"`. The remote currently serves `Qwen3.6-35B-A3B-GGUF:Q8_0`, declared in `opencode.json` under provider `ooz` with a 64k/8k limit. SSH connection details (host, user, port) are **delicate** and live in `ai.env` (gitignored), not in the repo. See the OOZ variables in the Configuration table.

## Architecture

### `ai.sh` — Single Bash function `ai()`

1. **Server lifecycle**:
   - `_start_server` — runs `omlx serve --model-dir … --paged-ssd-cache-dir …` with tuned cache/memory flags (binary resolved via `OMLX_BIN`, default `~/.omlx/venv/bin/omlx`). oMLX discovers models from `--model-dir` subdirectories, so no `--model` is passed; opencode picks the model per request.
   - `_wait_for_server` — polls `/v1/models` with spinner, opens tmux log pane if in tmux
   - `_kill_server` — kills by PID file then port scan (only targets python/mlx/omlx processes — the oMLX process renames itself to `omlx-server`)
2. **RAG**: Checks for `smart-coding-mcp` on launch (auto-indexes via opencode MCP config).
3. **OOZ tunnel** (`-ooz` only): `_start_tunnel` opens the SSH forward and polls the local port; `_discover_ooz_model` reads the served model id from `/v1/models`; `_kill_tunnel` kills the listener on the local port (only targets `ssh` processes).
4. **Frontend launch**: After server/endpoint healthy, runs `opencode -m "<provider>/<model-id>"` (`mlx/…` locally, `ooz/…` with `-ooz`; configured via `opencode.json`) in the caller's original `$PWD`. With `-cc` it instead launches `claude` against the local oMLX Anthropic endpoint.

### `opencode.json` — OpenCode provider config

Configures two providers: `mlx` (local, port 10081) and `ooz` (remote tunnel, port 8089), both OpenAI-compatible. The `ooz` provider declares `Qwen3.6-35B-A3B-GGUF:Q8_0` (the current remote model); the id passed via `-m` comes from `OOZ_MODEL` or runtime discovery and must match a declared id to pick up its limits. Context limit (64k), output limit (8k), and timeout. Also configures smart-coding-mcp for RAG indexing and enables the `opencode-mem` plugin via the top-level `"plugin"` array. `chrome-devtools` MCP is registered but disabled by default — flip `enabled` to true per-session if browser automation is needed.

### Memory — `opencode-mem` plugin (`opencode-mem.jsonc`)

Persistent cross-session memory for opencode. Activated by `"plugin": ["opencode-mem"]` in `opencode.json`; configured by `opencode-mem.jsonc` in this repo, symlinked to `~/.config/opencode/opencode-mem.jsonc` (same pattern as `opencode.json`). Fully local:

- **Storage**: SQLite (source of truth) at `~/.opencode-mem/data`; macOS uses Homebrew SQLite via `customSqlitePath`. Inspect with `sqlite3` or the web UI at `http://127.0.0.1:4747`.
- **Embeddings**: `bge-m3` (1024-dim, MLX/Metal) served by **oMLX** via `/v1/embeddings`. Setting `embeddingApiUrl` + `embeddingApiKey` in `opencode-mem.jsonc` switches the plugin off its in-process Xenova path onto the oMLX endpoint. (Switching from the old 768-dim nomic embeddings changes dimensions — if recall misbehaves on an existing store, clear `~/.opencode-mem/data` to force re-embedding.)
- **Auto-retain**: `autoCaptureEnabled` summarizes salient turns after idle. The summarizer is pointed at the **local oMLX server** (`memoryApiUrl: http://127.0.0.1:10081/v1`) — so capture stays on-box. It needs the oMLX server up (always true when launched via `ai.sh`). `autoCaptureMaxIterations` is raised to 8 now that oMLX's continuous batching lets the summarizer overlap coding turns instead of fighting a single decode slot.
- **Auto-recall**: `chatMessage` injects top memories at session start; `compaction` restores memories after context compaction.

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
| `OMLX_CACHE_DIR` | `~/.omlx/cache` | Paged SSD KV-cache directory |
| `OMLX_HOT_CACHE` | `12GB` | In-RAM hot KV-cache tier size |
| `OMLX_MEMORY_GUARD_GB` | `48` | Memory ceiling oMLX won't exceed (headroom on 64 GB) |
| `OMLX_MAX_CONCURRENT` | `4` | Max concurrent requests (continuous batching) |
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
- `claude` — required for `-cc` mode (Claude Code)
- `opencode` — frontend, sst/opencode (`brew install sst/tap/opencode`)
- `node` — required by the `opencode-mem` memory plugin (auto-installed by opencode from the `"plugin"` array)
- `smart-coding-mcp` — optional, for RAG (`npm install -g smart-coding-mcp`)
- **Models** live under `~/.omlx/models/` as MLX-format subdirectories. The Qwen weights are exposed by symlinking the HF cache snapshot to `~/.omlx/models/mlx-community/Qwen3.6-35B-A3B-6bit` (so the served id matches `opencode.json`); `bge-m3` (embeddings) is `mlx-community/bge-m3-mlx-fp16` downloaded into `~/.omlx/models/bge-m3`.

## Server Tuning

oMLX launches with explicit flags (see the `OMLX_*` Configuration vars):

- `--paged-ssd-cache-dir ~/.omlx/cache` — **the headline feature.** Block-based KV cache (vLLM-style, prefix sharing + copy-on-write) with a cold SSD tier; recurring prefixes (system prompt, shared codebase context) are restored from disk on a cache hit — even across a server restart — instead of recomputed. Measured locally: cold prefill ~2.3s → warm ~0.6s on a shared prefix.
- `--hot-cache-max-size 12GB` — in-RAM hot KV tier (oMLX default is 0/disabled; must be set explicitly). Bigger tier = more in-memory hits before spilling to SSD.
- `--memory-guard-gb 48` — hard ceiling oMLX won't exceed, leaving ~16 GB for macOS/apps on a 64 GB machine. Replaces the old `MLX_CACHE_LIMIT`. Raise on 128 GB configs.
- `--max-concurrent-requests 4` — continuous batching. Lets the opencode-mem summarizer overlap a coding turn instead of serializing on one slot.

oMLX auto-tunes the paged-cache block size (e.g. 2048 tokens for the Qwen hybrid model) and reads the model's native context (Qwen3.6 reports 262 144).

**Context window**: opencode advertises **65,536 tokens context / 8,192 output** for Qwen (`opencode.json`) — conservative vs the native 256 k window, leaving headroom on 64 GB with a 35B/6-bit model resident.

## Key Details

- Server port: **10081** (OpenAI `/v1`, Anthropic `/v1/messages`, embeddings `/v1/embeddings`, rerank `/v1/rerank`); oMLX admin/chat UI at `/admin`
- Logs: `$AI_LOG_DIR/omlx-server-<timestamp>.log` (ai.sh redirect); oMLX also writes `~/.omlx/logs/server.log`
- State file: `$AI_STATE_DIR/omlx-model` (single line: model id), PID file: `$AI_STATE_DIR/omlx-server.pid`
- Startup timeout: 120 seconds (oMLX binds in ~1–3s; first chat request lazily loads the ~30 GB model)
- In tmux: auto-opens split pane tailing server log
- The `logs/` directory is auto-pruned: `*.log` files older than 14 days are deleted at server start
- opencode config lives at `opencode.json` in this repo, symlinked from `~/.config/opencode/opencode.json`; `opencode-mem.jsonc` is symlinked the same way
- RAG: smart-coding-mcp with Xenova/all-MiniLM-L6-v2 embeddings, auto-indexes on opencode connect (still in-process; not yet moved to oMLX — it has no external-endpoint option)
- Memory: `opencode-mem` plugin — SQLite at `~/.opencode-mem/data`, `bge-m3` embeddings + summarizer both on the local oMLX server; web UI at `http://127.0.0.1:4747`
