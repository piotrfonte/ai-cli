# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Bash tool (`ai.sh`) that launches a local MLX inference server (via `mlx-lm`) and connects [opencode](https://github.com/opencode-ai/opencode) to it. The local model is Qwen 3.6 35B-A3B. With `-ooz`, it instead opens an SSH tunnel to a remote OpenAI-compatible endpoint and points opencode at that. Designed for Apple Silicon Macs (M4 Max with 64GB RAM assumed).

## Usage

```bash
bash ai.sh              # Qwen 3.6 (local MLX) + opencode
bash ai.sh -ooz         # SSH tunnel to the OOZ remote endpoint + opencode
bash ai.sh -k           # Kill the local server and OOZ tunnel
bash ai.sh -h           # Show help
bash ai.sh -- --flag    # Pass args through to the frontend
source ai.sh && ai      # Source as a function
```

### `-ooz` remote mode

`ai -ooz` skips the local MLX server. It opens an SSH tunnel (`ssh -f -N -C -L <local>:<remote> -p <port> <user>@<host>`) forwarding a local port to the remote's OpenAI-compatible server, polls the endpoint until healthy, resolves the model id (`OOZ_MODEL` if set, else auto-detected from `/v1/models`), then launches `opencode -m "ooz/<model-id>"`. The remote currently serves `Qwen3.6-35B-A3B-GGUF:Q8_0`, declared in `opencode.json` under provider `ooz` with a 64k/8k limit. SSH connection details (host, user, port) are **delicate** and live in `ai.env` (gitignored), not in the repo. See the OOZ variables in the Configuration table.

## Architecture

### `ai.sh` — Single Bash function `ai()`

1. **Server lifecycle**:
   - `_start_server` — runs `uv run --with mlx-lm mlx_lm.server` with tuned cache/concurrency flags
   - `_wait_for_server` — polls `/v1/models` with spinner, opens tmux log pane if in tmux
   - `_kill_server` — kills by PID file then port scan (only targets python/mlx processes)
2. **RAG**: Checks for `smart-coding-mcp` on launch (auto-indexes via opencode MCP config).
3. **OOZ tunnel** (`-ooz` only): `_start_tunnel` opens the SSH forward and polls the local port; `_discover_ooz_model` reads the served model id from `/v1/models`; `_kill_tunnel` kills the listener on the local port (only targets `ssh` processes).
4. **Frontend launch**: After server/endpoint healthy, runs `opencode -m "<provider>/<model-id>"` (`mlx/…` locally, `ooz/…` with `-ooz`; configured via `opencode.json`) in the caller's original `$PWD`.

### `opencode.json` — OpenCode provider config

Configures two providers: `mlx` (local, port 10081) and `ooz` (remote tunnel, port 8089), both OpenAI-compatible. The `ooz` provider declares `Qwen3.6-35B-A3B-GGUF:Q8_0` (the current remote model); the id passed via `-m` comes from `OOZ_MODEL` or runtime discovery and must match a declared id to pick up its limits. Context limit (64k), output limit (8k), and timeout. Also configures smart-coding-mcp for RAG indexing. `chrome-devtools` MCP is registered but disabled by default — flip `enabled` to true per-session if browser automation is needed.

## Configuration

Environment variables can be set in `ai.env` or exported before running.

| Variable | Default | Description |
|----------|---------|-------------|
| `AI_DIR` | auto-detected | Base directory of the tool |
| `AI_LOG_DIR` | `$AI_DIR/logs` | Server log directory |
| `AI_STATE_DIR` | `~/.local/state` | State and PID files |
| `AI_PORT` | `10081` | MLX server port |
| `MLX_CACHE_LIMIT` | `28991029248` | Metal buffer cache cap (27 GB, leaves headroom on 64 GB machines) |
| `OOZ_SSH_HOST` | — | Remote SSH host for `-ooz` (delicate; set in `ai.env`) |
| `OOZ_SSH_USER` | — | Remote SSH user for `-ooz` (delicate; set in `ai.env`) |
| `OOZ_SSH_PORT` | `22` | Remote SSH port for `-ooz` |
| `OOZ_LOCAL_PORT` | `8089` | Local forwarded port opencode connects to (must match `opencode.json` `ooz` baseURL) |
| `OOZ_REMOTE` | `127.0.0.1:8080` | Remote `host:port` the OpenAI-compatible endpoint listens on |
| `OOZ_MODEL` | auto-detect | Remote model id (must match an id declared in `opencode.json` provider `ooz`) |

The real `ai.env` is gitignored. `ai.env.example` holds commented placeholders for all of the above.

## Dependencies

- `uv` — Python package runner (local mode)
- `ssh` — required for `-ooz` remote mode
- `opencode` — frontend (`go install github.com/opencode-ai/opencode@latest`)
- `mlx-lm` — fetched automatically by `uv run --with`
- `smart-coding-mcp` — optional, for RAG (`npm install -g smart-coding-mcp`)

## Server Tuning

The server launches with explicit resource caps (not relying on MLX defaults, which grow unbounded):

- `MLX_CACHE_LIMIT` = 27 GB — Metal buffer cache cap, sized so a 35B/6-bit model (~30 GB resident) + KV cache + macOS + apps stays out of swap on 64 GB machines. Raise to ~48 GB on 128 GB configs.
- `--prompt-cache-bytes` = 8 GB — KV / prefix cache budget shared across cache slots
- `--prompt-cache-size` = 2 — two prefix slots so the system-prompt prefix survives when the user-turn prefix diverges
- `--max-tokens` = 8192 — caps decode tail length to avoid late-session memory pressure
- `--prefill-step-size` = 8192 — larger chunks reduce TTFT overhead on long prompts
- `--decode-concurrency 1 --prompt-concurrency 1` — fully serialized, no Metal contention

**Context window**: opencode advertises **65,536 tokens context / 8,192 output** for Qwen (`opencode.json`). Matches native Qwen3 64 k window and leaves headroom on 64 GB with a 35B/6-bit model resident.

## Key Details

- Server port: **10081**
- Logs: `$AI_LOG_DIR/mlx-lm-server-<timestamp>.log`
- State file: `$AI_STATE_DIR/mlx-lm-model` (single line: model id), PID file: `$AI_STATE_DIR/mlx-lm-server.pid`
- Startup timeout: 120 seconds
- In tmux: auto-opens split pane tailing server log
- The `logs/` directory is auto-pruned: `*.log` files older than 14 days are deleted at server start
- Opencode config lives at `opencode.json` in this repo (not `~/.config`)
- RAG: smart-coding-mcp with Xenova/all-MiniLM-L6-v2 embeddings, auto-indexes on opencode connect
