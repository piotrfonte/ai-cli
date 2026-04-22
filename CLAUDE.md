# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Bash tool (`ai.sh`) that launches a local MLX inference server (via `mlx-lm`) and connects [opencode](https://github.com/opencode-ai/opencode) to it. Defaults to Qwen 3.6 35B-A3B; `-glm` selects GLM-4.7 Flash. Designed for Apple Silicon Macs (M4 Max with 64GB RAM assumed).

## Usage

```bash
bash ai.sh              # Qwen 3.6 + opencode (default)
bash ai.sh -glm         # GLM-4.7 Flash
bash ai.sh -k           # Kill the running server
bash ai.sh -h           # Show help
bash ai.sh -- --flag    # Pass args through to opencode
source ai.sh && ai      # Source as a function
```

## Architecture

### `ai.sh` — Single Bash function `ai()`

1. **Server lifecycle**:
   - `_start_server` — runs `uv run --with mlx-lm mlx_lm.server` with tuned cache/concurrency flags
   - `_wait_for_server` — polls `/v1/models` with spinner, opens tmux log pane if in tmux
   - `_kill_server` — kills by PID file then port scan (only targets python/mlx processes)
2. **RAG**: Checks for `smart-coding-mcp` on launch (auto-indexes via opencode MCP config).
3. **Opencode launch**: After server healthy, runs `opencode -m "mlx/<model-id>"` in the caller's original `$PWD`.

### `opencode.json` — OpenCode provider config

Configures MLX (port 10080) as an OpenAI-compatible provider. Context limit (42k), output limit (8k), and timeout per model. Also configures smart-coding-mcp for RAG indexing.

## Configuration

Environment variables can be set in `ai.env` or exported before running.

| Variable | Default | Description |
|----------|---------|-------------|
| `AI_DIR` | auto-detected | Base directory of the tool |
| `AI_LOG_DIR` | `$AI_DIR/logs` | Server log directory |
| `AI_STATE_DIR` | `~/.local/state` | State and PID files |
| `AI_PORT` | `10080` | MLX server port |
| `MLX_CACHE_LIMIT` | `34359738368` | Metal buffer cache cap (32 GB, safe for 64 GB machines) |

## Dependencies

- `uv` — Python package runner
- `opencode` — AI coding TUI (`go install github.com/opencode-ai/opencode@latest`)
- `mlx-lm` — fetched automatically by `uv run --with`
- `smart-coding-mcp` — optional, for RAG (`npm install -g smart-coding-mcp`)

## Server Tuning

The server launches with explicit resource caps (not relying on MLX defaults, which grow unbounded):

- `MLX_CACHE_LIMIT` = 32 GB — Metal buffer cache cap, sized so a 35B/6-bit model (~30 GB resident) + macOS + apps stays out of swap on 64 GB machines. Raise to ~48 GB on 128 GB configs.
- `--prompt-cache-bytes` = 14 GB — single-slot KV cache for system prompt/prefix reuse
- `--prefill-step-size` = 8192 — larger chunks reduce TTFT overhead on long prompts
- `--decode-concurrency 1 --prompt-concurrency 1` — fully serialized, no Metal contention

**Context window**: opencode advertises **65,536 tokens context / 16,384 output** for both models (`opencode.json`). Matches native Qwen3 64 k window and leaves ~10 GB of RAM headroom on 64 GB with a 35B/6-bit model resident.

## Key Details

- Server port: **10080**
- Logs: `$AI_LOG_DIR/mlx-lm-server-<timestamp>.log`
- State file: `$AI_STATE_DIR/mlx-lm-model` (single line: model id), PID file: `$AI_STATE_DIR/mlx-lm-server.pid`
- Startup timeout: 120 seconds
- In tmux: auto-opens split pane tailing server log
- The `logs/` directory can grow large; old logs are not auto-cleaned
- Opencode config lives at `opencode.json` in this repo (not `~/.config`)
- RAG: smart-coding-mcp with Xenova/all-MiniLM-L6-v2 embeddings, auto-indexes on opencode connect
