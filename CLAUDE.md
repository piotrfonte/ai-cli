# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Bash tool (`ai.sh`) that launches a local MLX inference server (via `mlx-lm`) and connects [opencode](https://github.com/opencode-ai/opencode) to it. The model is Qwen 3.6 35B-A3B. Designed for Apple Silicon Macs (M4 Max with 64GB RAM assumed).

## Usage

```bash
bash ai.sh              # Qwen 3.6 + opencode
bash ai.sh -k           # Kill the running server
bash ai.sh -h           # Show help
bash ai.sh -- --flag    # Pass args through to the frontend
source ai.sh && ai      # Source as a function
```

## Architecture

### `ai.sh` — Single Bash function `ai()`

1. **Server lifecycle**:
   - `_start_server` — runs `uv run --with mlx-lm mlx_lm.server` with tuned cache/concurrency flags
   - `_wait_for_server` — polls `/v1/models` with spinner, opens tmux log pane if in tmux
   - `_kill_server` — kills by PID file then port scan (only targets python/mlx processes)
2. **RAG**: Checks for `smart-coding-mcp` on launch (auto-indexes via opencode MCP config).
3. **Frontend launch**: After server healthy, runs `opencode -m "mlx/<model-id>"` (configured via `opencode.json`) in the caller's original `$PWD`.

### `opencode.json` — OpenCode provider config

Configures MLX (port 10081) as an OpenAI-compatible provider. Context limit (64k), output limit (8k), and timeout. Also configures smart-coding-mcp for RAG indexing. `chrome-devtools` MCP is registered but disabled by default — flip `enabled` to true per-session if browser automation is needed.

## Configuration

Environment variables can be set in `ai.env` or exported before running.

| Variable | Default | Description |
|----------|---------|-------------|
| `AI_DIR` | auto-detected | Base directory of the tool |
| `AI_LOG_DIR` | `$AI_DIR/logs` | Server log directory |
| `AI_STATE_DIR` | `~/.local/state` | State and PID files |
| `AI_PORT` | `10081` | MLX server port |
| `MLX_CACHE_LIMIT` | `28991029248` | Metal buffer cache cap (27 GB, leaves headroom on 64 GB machines) |

## Dependencies

- `uv` — Python package runner
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
