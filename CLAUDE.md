# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Bash tool (`ai.sh`) that launches a local MLX inference server (GLM-4.7 Flash via mlx-lm) and connects [opencode](https://github.com/opencode-ai/opencode) to it. Designed for Apple Silicon Macs (M4 Max with 64GB RAM assumed).

## Usage

```bash
bash ai.sh              # Start GLM Flash via mlx-lm + opencode
bash ai.sh -k           # Kill running server
bash ai.sh -h           # Show help
bash ai.sh -- --flag    # Pass args through to opencode
source ai.sh && ai      # Source as a function
```

## Architecture

### `ai.sh` — Single Bash function `ai()`

1. **Server lifecycle**:
   - `_start_server` — runs `uv run --with mlx-lm python mlx_server.py`
   - `_wait_for_server` — polls `/v1/models` with spinner, opens tmux log pane if in tmux
   - `_kill_server` — kills listener + parent PID, escalates to SIGKILL after 5s
2. **Model switching**: If a server is running with a different model, it auto-restarts with the requested one.
3. **RAG**: Checks for `smart-coding-mcp` on launch (auto-indexes via opencode MCP config).
4. **Opencode launch**: After server healthy, runs `opencode -m "mlx/<model-id>"` in the caller's original `$PWD`.

### `mlx_server.py` — Wrapper for mlx-lm with cache cap + tool-call loop detection

Caps MLX Metal buffer cache at 2GB via `mx.set_cache_limit()` before calling `mlx_lm.server.main()`. Monkey-patches the HTTP handler to detect tool-call loops: when a request contains more than 25 tool messages, strips tools from the request so the model generates a normal text response instead of looping.

## Configuration

Environment variables can be set in `ai.env` or exported before running. See `ai.env` for all options.

| Variable | Default | Description |
|----------|---------|-------------|
| `AI_DIR` | auto-detected | Base directory of the tool |
| `AI_LOG_DIR` | `$AI_DIR/logs` | Server log directory |
| `AI_STATE_DIR` | `~/.local/state` | State and PID files |
| `AI_PORT` | `10080` | Server port |

## Dependencies

- `uv` — Python package runner
- `opencode` — AI coding TUI (`go install github.com/opencode-ai/opencode@latest`)
- `mlx-lm` — fetched automatically by `uv run --with`
- `smart-coding-mcp` — optional, for RAG (`npm install -g smart-coding-mcp`)

## Key Details

- Server port: **10080** (configurable via `AI_PORT`)
- Logs: `$AI_LOG_DIR/mlx-lm-server-<timestamp>.log`
- Startup timeout: 120 seconds
- State file: `$AI_STATE_DIR/mlx-lm-model`
- PID file: `$AI_STATE_DIR/mlx-lm-server.pid`
- In tmux: auto-opens split pane tailing server log
- The `logs/` directory can grow large; old logs are not auto-cleaned
- Opencode config: `~/.config/opencode/opencode.json`
- RAG: smart-coding-mcp with Xenova/all-MiniLM-L6-v2 embeddings, auto-indexes on opencode connect
