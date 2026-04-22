# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Bash tool (`ai.sh`) that launches a local MLX inference server and connects [opencode](https://github.com/opencode-ai/opencode) to it. Defaults to Qwen 3.6 35B-A3B on the **vllm-mlx** backend; GLM-4.7 Flash (`-glm`) defaults to the **mlx-lm** backend. Backend choice per model can be forced with `-vllm` or `-mlx`. Designed for Apple Silicon Macs (M4 Max with 64GB RAM assumed).

## Usage

```bash
bash ai.sh              # Qwen 3.6 on vllm-mlx + opencode (default)
bash ai.sh -glm         # GLM-4.7 Flash on mlx-lm
bash ai.sh -mlx         # Force Qwen onto mlx-lm
bash ai.sh -vllm -glm   # Force GLM onto vllm-mlx
bash ai.sh -k           # Kill whichever backend is running
bash ai.sh -h           # Show help
bash ai.sh -- --flag    # Pass args through to opencode
source ai.sh && ai      # Source as a function
```

## Architecture

### `ai.sh` — Single Bash function `ai()`

1. **Server lifecycle**:
   - `_start_server` — dispatches to `_start_server_mlx` or `_start_server_vllm` based on `$backend`
   - `_start_server_mlx` — runs `uv run --with mlx-lm mlx_lm.server` with tuned cache/concurrency flags
   - `_start_server_vllm` — runs `uvx --from git+https://github.com/waybarrios/vllm-mlx.git vllm-mlx serve`
   - `_wait_for_server` — polls `/v1/models` with spinner, opens tmux log pane if in tmux; both backends expose the same endpoint
   - `_kill_server` — kills by PID file then port scan; backend-agnostic (both run as Python/MLX processes)
2. **RAG**: Checks for `smart-coding-mcp` on launch (auto-indexes via opencode MCP config).
3. **Opencode launch**: After server healthy, runs `opencode -m "mlx/<model-id>"` in the caller's original `$PWD`. Both backends share the `mlx` provider in `opencode.json` since they share port 10080.

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

- `uv` — Python package runner (provides `uvx` used by the vllm-mlx backend)
- `opencode` — AI coding TUI (`go install github.com/opencode-ai/opencode@latest`)
- `mlx-lm` — fetched automatically by `uv run --with` (mlx-lm backend)
- `vllm-mlx` — fetched automatically by `uvx --from git+...` (vllm-mlx backend, opt-in via `-vllm`)
- `smart-coding-mcp` — optional, for RAG (`npm install -g smart-coding-mcp`)

## Backends

Backend is model-defaulted: each model profile declares a `model_default_backend`, and `-vllm`/`-mlx` overrides it.

| Backend | Default for | Flag | Strengths | Tradeoff |
|---------|-------------|------|-----------|----------|
| `mlx-lm` | GLM | `-mlx` | Apple's official serve path; stable; explicit prompt-cache tuning | No prefix-cache sharing across turns; no paged KV |
| `vllm-mlx` | Qwen | `-vllm` | Prefix caching (~1.55× on warm prompts), paged KV, Anthropic `/v1/messages` endpoint, reasoning parser for Qwen3 | Third-party (Apache-2.0); continuous-batching gains unused in single-client workflows |

Both backends serve on port 10080 with OpenAI-compatible `/v1/*` endpoints, so `opencode.json` needs no changes to switch. State file records which backend is running so that switching triggers a clean kill+restart.

## Server Tuning

Servers launch with explicit resource caps (not relying on MLX defaults, which grow unbounded):

**Shared**
- `MLX_CACHE_LIMIT` = 32 GB — Metal buffer cache cap, sized so a 35B/6-bit model (~30 GB resident) + macOS + apps stays out of swap on 64 GB machines. Raise to ~48 GB on 128 GB configs.

**mlx-lm**
- `--prompt-cache-bytes` = 14 GB — single-slot KV cache for system prompt/prefix reuse
- `--prefill-step-size` = 8192 — larger chunks reduce TTFT overhead on long prompts
- `--decode-concurrency 1 --prompt-concurrency 1` — fully serialized, no Metal contention

**vllm-mlx**
- `--cache-memory-mb` = 14336 — prefix + paged KV budget; bigger cache raises the prefix-cache hit rate (published ~1.55× on warm prompts)
- `--max-cache-blocks 3000` — paged-cache block-count cap (3000 × 64 tokens = 192 k token capacity). Default 1000 would silently cap at 64 k regardless of byte budget.
- `--use-paged-cache` — enables paged KV (~1.12× on published M4 Max benchmarks)
- `--max-num-seqs 1` — preserves the single-slot tuning; raise later if a concurrent workload justifies it
- `--enable-auto-tool-choice` — required for opencode's `tool_choice: auto` semantics
- `--tool-call-parser` — per-model: `hermes` for Qwen3 (emits `<tool_call>…</tool_call>` XML), `glm47` for GLM; driven by `model_tool_call_parser`. The legacy `qwen` parser is for Qwen2's `function_call` format and mis-parses parallel tool calls on Qwen3.
- `--reasoning-parser qwen3` — only applied for Qwen models (`model_reasoning_parser` field)

**Context window**: opencode advertises **65,536 tokens context / 16,384 output** for both models (`opencode.json`). Matches native Qwen3 64 k window and leaves ~10 GB of RAM headroom on 64 GB with a 35B/6-bit model resident.

## Key Details

- Server port (shared across backends): **10080**
- Logs: `$AI_LOG_DIR/{mlx-lm,vllm-mlx}-server-<timestamp>.log`
- State file: `$AI_STATE_DIR/mlx-lm-model` (2 lines: backend on line 1, model id on line 2), PID file: `$AI_STATE_DIR/mlx-lm-server.pid`
- Startup timeout: 120 seconds
- In tmux: auto-opens split pane tailing server log
- The `logs/` directory can grow large; old logs are not auto-cleaned
- Opencode config lives at `opencode.json` in this repo (not `~/.config`)
- RAG: smart-coding-mcp with Xenova/all-MiniLM-L6-v2 embeddings, auto-indexes on opencode connect
