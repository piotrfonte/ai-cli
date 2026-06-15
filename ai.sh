#!/usr/bin/env bash
# ai.sh — MLX Inference Server Launcher
# Usage: bash ai.sh [OPTIONS] [-- frontend-args...]
#   or:  source ai.sh && ai [OPTIONS] [-- frontend-args...]

ai() {
  local caller_dir="$PWD"

  # ── ANSI colors (tty-gated) ──────────────────────────────────────────
  local c_reset c_cyan c_bold c_green c_red c_dim c_yellow
  if [[ -t 1 ]]; then
    c_reset=$'\033[0m'
    c_cyan=$'\033[36m'
    c_bold=$'\033[1m'
    c_green=$'\033[32m'
    c_red=$'\033[31m'
    c_dim=$'\033[2m'
    c_yellow=$'\033[33m'
  else
    c_reset='' c_cyan='' c_bold='' c_green='' c_red='' c_dim='' c_yellow=''
  fi

  # ── Box-drawing helpers ──────────────────────────────────────────────
  local box_w=55
  _box_rule() {
    local l="$1" r="$2" line=""
    for (( i=0; i<box_w; i++ )); do line+="─"; done
    printf "  %s%s%s%s%s\n" "${c_cyan}${l}" "$line" "${r}${c_reset}" "" ""
  }
  _box_top()    { _box_rule "╭" "╮"; }
  _box_mid()    { _box_rule "├" "┤"; }
  _box_bottom() { _box_rule "╰" "╯"; }
  _box_line() {
    local content="$1"
    local visible
    visible=$(printf '%s' "$content" | sed $'s/\033\\[[0-9;]*m//g')
    local vlen=${#visible}
    if (( vlen >= box_w )); then
      printf "  ${c_cyan}│${c_reset}%s${c_cyan}│${c_reset}\n" "$content"
    else
      local pad=$((box_w - vlen))
      printf "  ${c_cyan}│${c_reset}%s%*s${c_cyan}│${c_reset}\n" "$content" "$pad" ""
    fi
  }
  _box_empty() { _box_line ""; }

  # ── Configurable paths (override via environment) ────────────────────
  local ai_dir="${AI_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
  # shellcheck disable=SC1091
  [[ -f "${ai_dir}/ai.env" ]] && source "${ai_dir}/ai.env"
  local ai_log_dir="${AI_LOG_DIR:-${ai_dir}/logs}"
  local ai_state_dir="${AI_STATE_DIR:-${HOME}/.local/state}"

  # ── MLX model config ──────────────────────────────────────────────────
  local model_id model_label model_context_limit
  local server_port="${AI_PORT:-10081}"
  local state_file="${ai_state_dir}/omlx-model"
  local pid_file="${ai_state_dir}/omlx-server.pid"
  local startup_timeout=120

  # ── oMLX server config (override via environment) ────────────────────
  # oMLX is a native Apple-Silicon inference server with a two-tier KV cache
  # (hot RAM + cold SSD) that restores recurring prefixes from disk instead of
  # recomputing them — the agentic-coding win. Built from source into a venv;
  # see CLAUDE.md for the build steps.
  local omlx_bin="${OMLX_BIN:-}"
  if [[ -z "$omlx_bin" ]]; then
    if command -v omlx >/dev/null 2>&1; then
      omlx_bin="omlx"
    else
      omlx_bin="${HOME}/.omlx/venv/bin/omlx"
    fi
  fi
  local omlx_model_dir="${OMLX_MODEL_DIR:-${HOME}/.omlx/models}"
  local omlx_cache_dir="${OMLX_CACHE_DIR:-${HOME}/.omlx/cache}"
  local omlx_hot_cache="${OMLX_HOT_CACHE:-8GB}"       # in-RAM hot KV tier; model+tier must stay under the guard's soft threshold (85%)
  local omlx_ssd_cache_max="${OMLX_SSD_CACHE_MAX:-40GB}"    # disk cap; oMLX defaults to nearly all free space
  local omlx_memory_guard_gb="${OMLX_MEMORY_GUARD_GB:-48}"  # ceiling on 64 GB box
  local omlx_max_concurrent="${OMLX_MAX_CONCURRENT:-2}"     # continuous batching: 1 coding turn + 1 opencode-mem summarizer

  # ── OOZ remote endpoint config (used by -ooz; set in ai.env) ─────────
  local ooz_ssh_host="${OOZ_SSH_HOST:-}"
  local ooz_ssh_user="${OOZ_SSH_USER:-}"
  local ooz_ssh_port="${OOZ_SSH_PORT:-22}"
  local ooz_local_port="${OOZ_LOCAL_PORT:-8089}"
  local ooz_remote="${OOZ_REMOTE:-127.0.0.1:8080}"
  local ooz_model="${OOZ_MODEL:-}"   # pin model id; empty → auto-detect

  # ── Model profile ────────────────────────────────────────────────────
  # model_id must match a model oMLX serves from --model-dir (the two-level
  # mlx-community/<name> form is accepted) AND the id keyed in opencode.json.
  _model_qwen() {
    model_id="mlx-community/Qwen3.6-35B-A3B-6bit"
    model_label="Qwen 3.6 35B-A3B 6-bit"
    model_context_limit=65536
  }

  # Same 35B-A3B MoE as the default (3B active params → same decode speed) but at
  # 4-bit instead of 6-bit: ~20 GB resident vs ~27.5 GB. The freed memory means the
  # Metal-cap throttling that forced the 6-bit down to 49 k doesn't bind, so
  # opencode.json advertises a larger 65 k window.
  _model_qwen_light() {
    model_id="mlx-community/Qwen3.6-35B-A3B-4bit"
    model_label="Qwen 3.6 35B-A3B 4-bit (light)"
    model_context_limit=65536
  }

  local oc_provider="mlx"

  # ── Helpers ──────────────────────────────────────────────────────────
  _info()  { printf "  ${c_cyan}▸${c_reset} %s\n" "$*"; }
  _ok()    { printf "  ${c_green}✔${c_reset} %s\n" "$*"; }
  _err()   { printf "  ${c_red}✘${c_reset} %s\n" "$*" >&2; }
  _warn()  { printf "  ${c_yellow}▸${c_reset} %s\n" "$*"; }

  _server_pid() {
    lsof -ti "tcp:${server_port}" -sTCP:LISTEN 2>/dev/null | head -1
  }

  _server_healthy() {
    curl -sf --max-time 2 "http://localhost:${server_port}/v1/models" >/dev/null 2>&1
  }

  # Warn if another opencode session is already serving a *different* local model.
  # oMLX is multi-model and lazy-loads whatever model id a request asks for, so a
  # lingering opencode from a previous `ai`/`ai -light` run keeps requesting its
  # model — and oMLX loads it alongside ours. Two ~20-28GB LLMs can't coexist
  # under the memory guard, so it thrashes (evict/reload) and stalls or 507s
  # requests mid-turn (the agent "chokes"). Restarting our server can't stop the
  # other client, so we can only detect the conflict and tell the user to clear
  # it. Each opencode's command line carries `-m mlx/<id>`, so we know its model.
  _warn_model_conflict() {
    [[ "$oc_provider" == "mlx" ]] || return 0   # only the local provider competes for oMLX memory
    local pid args pmodel conflict=0
    for pid in $(pgrep -x opencode 2>/dev/null); do
      args=$(ps -o args= -p "$pid" 2>/dev/null)
      case "$args" in *" -m "*) ;; *) continue ;; esac
      pmodel=${args##*-m }; pmodel=${pmodel%% *}; pmodel=${pmodel#mlx/}
      [[ -n "$pmodel" && "$pmodel" != "$model_id" ]] || continue
      _warn "Another opencode (PID ${pid}) is serving ${c_bold}${pmodel}${c_reset}"
      conflict=1
    done
    if (( conflict )); then
      _warn "Two local models would co-reside in oMLX and thrash memory — this is what stalls/507s requests mid-turn."
      _info "Close that session, then ${c_dim}ai -k${c_reset} before switching models."
    fi
  }

  _kill_server() {
    rm -f "$state_file"
    local pids_to_kill=""

    # Primary: use PID file written at server startup
    if [[ -f "$pid_file" ]]; then
      local saved_pid
      saved_pid=$(cat "$pid_file" 2>/dev/null)
      if [[ -n "$saved_pid" ]] && kill -0 "$saved_pid" 2>/dev/null; then
        pids_to_kill="$pids_to_kill $saved_pid"
        # Also get parent (the uv/python wrapper)
        local ppid
        ppid=$(ps -o ppid= -p "$saved_pid" 2>/dev/null | tr -d ' ')
        if [[ -n "$ppid" && "$ppid" != "1" ]]; then
          pids_to_kill="$pids_to_kill $ppid"
        fi
      fi
      rm -f "$pid_file"
    fi

    # Fallback: port scan, but only kill python/mlx processes
    if [[ -z "$pids_to_kill" ]]; then
      local port_pids
      port_pids=$(lsof -ti "tcp:${server_port}" -sTCP:LISTEN 2>/dev/null)
      for pid in $port_pids; do
        local cmd_name
        cmd_name=$(ps -o comm= -p "$pid" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        if [[ "$cmd_name" == *python* || "$cmd_name" == *mlx* || "$cmd_name" == *omlx* ]]; then
          pids_to_kill="$pids_to_kill $pid"
        else
          _warn "Skipping unknown process on port ${server_port}: ${cmd_name} (PID ${pid})"
        fi
      done
    fi

    if [[ -n "$pids_to_kill" ]]; then
      kill $pids_to_kill 2>/dev/null
      local waited=0
      while lsof -ti "tcp:${server_port}" -sTCP:LISTEN >/dev/null 2>&1 && (( waited < 10 )); do
        sleep 0.5
        (( waited++ ))
      done
      # Only SIGKILL our own processes, not anything else on the port
      local remaining
      remaining=$(lsof -ti "tcp:${server_port}" -sTCP:LISTEN 2>/dev/null)
      if [[ -n "$remaining" ]]; then
        for pid in $remaining; do
          local cmd_name
          cmd_name=$(ps -o comm= -p "$pid" 2>/dev/null | tr '[:upper:]' '[:lower:]')
          if [[ "$cmd_name" == *python* || "$cmd_name" == *mlx* || "$cmd_name" == *omlx* ]]; then
            kill -9 "$pid" 2>/dev/null
          fi
        done
      fi
      _ok "Server stopped"
    else
      _info "No server running on port ${server_port}"
    fi
  }

  # ── OOZ SSH tunnel lifecycle ─────────────────────────────────────────
  _tunnel_healthy() {
    curl -sf --max-time 2 "http://127.0.0.1:${ooz_local_port}/v1/models" >/dev/null 2>&1
  }

  _kill_tunnel() {
    local port_pids
    port_pids=$(lsof -ti "tcp:${ooz_local_port}" -sTCP:LISTEN 2>/dev/null)
    local killed=""
    for pid in $port_pids; do
      local cmd_name
      cmd_name=$(ps -o comm= -p "$pid" 2>/dev/null | tr '[:upper:]' '[:lower:]')
      if [[ "$cmd_name" == *ssh* ]]; then
        kill "$pid" 2>/dev/null && killed="$killed $pid"
      fi
    done
    [[ -n "$killed" ]] && _ok "Tunnel closed${c_dim} (PID${killed})${c_reset}"
  }

  _start_tunnel() {
    if [[ -z "$ooz_ssh_host" || -z "$ooz_ssh_user" ]]; then
      _err "OOZ endpoint not configured"
      _info "Set ${c_bold}OOZ_SSH_HOST${c_reset} and ${c_bold}OOZ_SSH_USER${c_reset} in ${c_dim}${ai_dir}/ai.env${c_reset}"
      return 1
    fi

    if _tunnel_healthy; then
      _ok "Tunnel already up${c_dim} (127.0.0.1:${ooz_local_port})${c_reset}"
      return 0
    fi

    echo ""
    _box_top
    _box_line " ${c_bold}Opening SSH Tunnel${c_reset}"
    _box_mid
    _box_line " ${c_bold}Remote:${c_reset} ${ooz_ssh_user}@${ooz_ssh_host}:${ooz_ssh_port}"
    _box_line " ${c_bold}Forward:${c_reset} 127.0.0.1:${ooz_local_port} → ${ooz_remote}"
    _box_bottom
    echo ""

    # -f backgrounds after auth + forward setup (so a passphrase prompt
    # still works); ExitOnForwardFailure makes a bind failure fatal.
    ssh -f -N -C \
      -o ExitOnForwardFailure=yes \
      -L "${ooz_local_port}:${ooz_remote}" \
      -p "${ooz_ssh_port}" \
      "${ooz_ssh_user}@${ooz_ssh_host}" || {
      _err "SSH tunnel failed to establish"
      return 1
    }

    local elapsed=0
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local fi=0
    while (( elapsed < 30 )); do
      if _tunnel_healthy; then
        printf "\r                                                    \r"
        _ok "Tunnel ready${c_dim} (127.0.0.1:${ooz_local_port}, took ${elapsed}s)${c_reset}"
        return 0
      fi
      printf "\r  ${c_cyan}${frames[$fi]}${c_reset} Waiting for endpoint... ${c_dim}(${elapsed}s)${c_reset}"
      fi=$(( (fi + 1) % ${#frames[@]} ))
      sleep 1
      (( elapsed++ ))
    done

    printf "\r                                                    \r"
    _err "Endpoint at 127.0.0.1:${ooz_local_port} did not respond within 30s"
    _kill_tunnel
    return 1
  }

  _discover_ooz_model() {
    curl -sf --max-time 5 "http://127.0.0.1:${ooz_local_port}/v1/models" 2>/dev/null \
      | tr ',{}' '\n\n\n' \
      | grep -m1 '"id"' \
      | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
  }

  # ── Show help ────────────────────────────────────────────────────────
  _show_help() {
    echo ""
    _box_top
    _box_line " ${c_bold}ai.sh${c_reset} — Local Inference Launcher"
    _box_bottom
    echo ""
    printf "  ${c_bold}Usage:${c_reset}  ai.sh [OPTIONS] [-- frontend-args...]\n"
    echo ""
    printf "  ${c_bold}Options:${c_reset}\n"
    printf "    ${c_cyan}-light, --light${c_reset}      Use the lighter Qwen 3.6 35B-A3B 4-bit model\n"
    printf "    ${c_cyan}-ooz,   --ooz${c_reset}        Tunnel to the OOZ remote endpoint\n"
    printf "    ${c_cyan}-cc,    --claude-code${c_reset} Launch Claude Code on local oMLX ${c_dim}(experimental)${c_reset}\n"
    printf "    ${c_cyan}-k,     --kill${c_reset}       Kill the oMLX server and OOZ tunnel\n"
    printf "    ${c_cyan}-h,     --help${c_reset}       Show this help\n"
    echo ""
    printf "  ${c_bold}Model:${c_reset}\n"
    printf "    ${c_dim}Qwen 3.6 35B-A3B 6-bit (local, default)${c_reset}\n"
    printf "    ${c_dim}Qwen 3.6 35B-A3B 4-bit (local, via -light)${c_reset}\n"
    printf "    ${c_dim}remote model via -ooz (auto-detected)${c_reset}\n"
    echo ""
  }

  # ── Ensure the selected model is on disk ─────────────────────────────
  # oMLX lazily loads weights from --model-dir on the first request, so a model
  # that isn't downloaded yet would only fail at that point. We pull it eagerly
  # here (before the server starts) following the existing layout: download into
  # the HF cache, then symlink the snapshot into ~/.omlx/models/mlx-community/<name>
  # (matching how the 35B is exposed). Idempotent — a no-op once the weights exist.
  _ensure_model() {
    local target="${omlx_model_dir}/${model_id}"
    if [[ -e "$target" ]] && compgen -G "${target}/*.safetensors" >/dev/null 2>&1; then
      return 0
    fi

    # Resolve a Hugging Face downloader — prefer the oMLX venv's, then PATH.
    local hf_bin=""
    for cand in \
      "$(dirname "$omlx_bin")/hf" \
      "$(dirname "$omlx_bin")/huggingface-cli" \
      "$(command -v hf 2>/dev/null)" \
      "$(command -v huggingface-cli 2>/dev/null)"; do
      if [[ -n "$cand" && -x "$cand" ]]; then hf_bin="$cand"; break; fi
    done
    if [[ -z "$hf_bin" ]]; then
      _err "No Hugging Face downloader (hf/huggingface-cli) found"
      _info "Expected in the oMLX venv: ${c_dim}${HOME}/.omlx/venv/bin/hf${c_reset}"
      return 1
    fi

    echo ""
    _box_top
    _box_line " ${c_bold}Downloading model${c_reset}"
    _box_mid
    _box_line " ${c_dim}${model_id}${c_reset}"
    _box_line " ${c_dim}one-time download (~16 GB) — progress below${c_reset}"
    _box_bottom
    echo ""

    # hf/huggingface-cli streams progress to stderr and prints the resolved
    # snapshot path to stdout as its last line; capture that, let progress through.
    # The hf 1.x CLI (huggingface_hub >=1.0) prefixes the path line with "path=" —
    # we strip it below; older CLIs print the bare path, so the strip is a no-op
    # there. HF_XET_HIGH_PERFORMANCE enables the fast Xet transfer backend (the
    # old HF_HUB_ENABLE_HF_TRANSFER is deprecated in 1.x and only emits a warning).
    local snapshot
    snapshot=$(HF_XET_HIGH_PERFORMANCE=1 "$hf_bin" download "$model_id" | tail -1) || {
      _err "Download failed for ${model_id}"
      return 1
    }
    snapshot="${snapshot#path=}"   # hf 1.x prints "path=<dir>"; older CLIs bare
    if [[ -z "$snapshot" || ! -d "$snapshot" ]]; then
      _err "Download did not yield a snapshot directory"
      return 1
    fi

    mkdir -p "$(dirname "$target")"
    ln -sfn "$snapshot" "$target"
    _ok "Model ready ${c_dim}(${target})${c_reset}"
  }

  # ── Start inference server ────────────────────────────────────────────
  _start_server() {
    echo ""
    _box_top
    _box_line " ${c_bold}Starting oMLX Server${c_reset}"
    _box_mid
    _box_line " ${c_bold}Model:${c_reset} ${model_label}"
    _box_line " ${c_dim}${model_id}${c_reset}"
    _box_line " ${c_bold}Port:${c_reset}  ${server_port}"
    _box_line " ${c_bold}KV:${c_reset}    hot ${omlx_hot_cache} + SSD ≤${omlx_ssd_cache_max} ${c_dim}${omlx_cache_dir}${c_reset}"
    _box_bottom
    echo ""

    mkdir -p "$(dirname "$state_file")" "$omlx_cache_dir" "$omlx_model_dir"
    local log_dir="${ai_log_dir}"
    mkdir -p "$log_dir"
    find "$log_dir" -maxdepth 1 -type f -name '*.log' -mtime +14 -delete 2>/dev/null
    local server_log="${log_dir}/omlx-server-$(date +%Y%m%d-%H%M%S).log"

    # oMLX discovers models from --model-dir subdirectories; opencode picks the
    # model per request, so we don't pass --model. The paged SSD cache + hot
    # RAM tier are what collapse agentic time-to-first-token from ~30s to ~1s.
    "$omlx_bin" serve \
      --model-dir "$omlx_model_dir" \
      --port "$server_port" \
      --paged-ssd-cache-dir "$omlx_cache_dir" \
      --paged-ssd-cache-max-size "$omlx_ssd_cache_max" \
      --hot-cache-max-size "$omlx_hot_cache" \
      --memory-guard-gb "$omlx_memory_guard_gb" \
      --max-concurrent-requests "$omlx_max_concurrent" \
      --log-level info \
      >"$server_log" 2>&1 &
    local server_pid=$!
    echo "$server_pid" > "$pid_file"

    _wait_for_server "$server_pid" "$server_log"
  }

  # ── Wait for server to become healthy ──────────────────────────────
  _wait_for_server() {
    local server_pid=$1
    local server_log=$2

    trap '_kill_server; _err "Interrupted"; return 130' INT

    if [[ -n "$TMUX" ]] && command -v tmux >/dev/null 2>&1; then
      tmux split-window -v -l 12 "tail -f '$server_log'"
    fi

    local elapsed=0
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local fi=0

    while (( elapsed < startup_timeout )); do
      if ! kill -0 "$server_pid" 2>/dev/null; then
        printf "\r                                                    \r"
        _err "Server process exited unexpectedly"
        _err "Check log: ${server_log}"
        rm -f "$pid_file"
        trap - INT
        return 1
      fi

      if _server_healthy; then
        printf "\r                                                    \r"
        _ok "Server ready ${c_dim}(PID ${server_pid}, took ${elapsed}s)${c_reset}"
        printf "%s\n" "$model_id" > "$state_file"
        trap - INT
        return 0
      fi

      printf "\r  ${c_cyan}${frames[$fi]}${c_reset} Waiting for server... ${c_dim}(${elapsed}s)${c_reset}"
      fi=$(( (fi + 1) % ${#frames[@]} ))
      sleep 1
      (( elapsed++ ))
    done

    printf "\r                                                    \r"
    _err "Server failed to start within ${startup_timeout}s"
    kill "$server_pid" 2>/dev/null
    rm -f "$pid_file"
    _err "Check log: ${server_log}"
    trap - INT
    return 1
  }

  # ── Reap orphaned MCP children from prior sessions ───────────────────
  _reap_orphan_mcps() {
    local reaped=0
    local patterns=("smart-coding-mcp --workspace" "chrome-devtools-mcp")
    for pat in "${patterns[@]}"; do
      while IFS= read -r mcp_pid; do
        [[ -z "$mcp_pid" ]] && continue
        local ppid
        ppid=$(ps -o ppid= -p "$mcp_pid" 2>/dev/null | tr -d ' ')
        if [[ "$ppid" == "1" ]]; then
          kill "$mcp_pid" 2>/dev/null && (( reaped++ ))
        fi
      done < <(pgrep -f "$pat" 2>/dev/null)
    done
    # opencode-mem web UI left bound on its port after opencode died (only
    # reap orphaned node/bun listeners — never some other app on 4747).
    while IFS= read -r web_pid; do
      [[ -z "$web_pid" ]] && continue
      local wppid wcmd
      wppid=$(ps -o ppid= -p "$web_pid" 2>/dev/null | tr -d ' ')
      wcmd=$(ps -o comm= -p "$web_pid" 2>/dev/null | tr '[:upper:]' '[:lower:]')
      if [[ "$wppid" == "1" && ( "$wcmd" == *node* || "$wcmd" == *bun* ) ]]; then
        kill "$web_pid" 2>/dev/null && (( reaped++ ))
      fi
    done < <(lsof -ti tcp:4747 -sTCP:LISTEN 2>/dev/null)
    (( reaped > 0 )) && _info "Reaped ${reaped} orphaned MCP process(es)"
  }

  # ── Dependency checks (mode-aware) ───────────────────────────────────
  _check_deps() {
    local missing=0
    if [[ "$mode" == "cc" ]]; then
      if ! command -v claude >/dev/null 2>&1; then
        _err "Missing dependency: ${c_bold}claude${c_reset} (Claude Code)"
        _info "Install: ${c_dim}https://claude.com/claude-code${c_reset}"
        missing=1
      fi
    elif ! command -v opencode >/dev/null 2>&1; then
      _err "Missing dependency: ${c_bold}opencode${c_reset}"
      _info "Install: ${c_dim}go install github.com/opencode-ai/opencode@latest${c_reset}"
      missing=1
    fi
    if [[ "$mode" == "ooz" ]]; then
      if ! command -v ssh >/dev/null 2>&1; then
        _err "Missing dependency: ${c_bold}ssh${c_reset}"
        missing=1
      fi
    elif [[ ! -x "$omlx_bin" ]] && ! command -v omlx >/dev/null 2>&1; then
      _err "Missing dependency: ${c_bold}omlx${c_reset} (expected at ${c_dim}${omlx_bin}${c_reset})"
      _info "Build: ${c_dim}git clone https://github.com/jundot/omlx ~/.omlx/src \\"
      _info "  && uv venv ~/.omlx/venv --python 3.12 \\"
      _info "  && VIRTUAL_ENV=~/.omlx/venv uv pip install -e ~/.omlx/src${c_reset}"
      missing=1
    fi
    return $missing
  }

  # ── Main logic ───────────────────────────────────────────────────────
  local action=""               # "" | "kill" | "help"
  local mode="local"            # "local" | "ooz" | "cc"
  local profile="default"       # "default" (35B-A3B 6-bit) | "light" (35B-A3B 4-bit)
  local -a passthrough_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -k|--kill)
        action="kill"
        shift
        ;;
      -h|--help)
        action="help"
        shift
        ;;
      -ooz|--ooz)
        mode="ooz"
        shift
        ;;
      -cc|--claude-code)
        mode="cc"
        shift
        ;;
      -light|--light)
        profile="light"
        shift
        ;;
      --)
        shift
        passthrough_args=("$@")
        break
        ;;
      *)
        _err "Unknown option: $1"
        _show_help
        return 1
        ;;
    esac
  done

  # ── Select model profile (local default) ─────────────────────────────
  case "$profile" in
    light) _model_qwen_light ;;
    *)     _model_qwen ;;
  esac
  local oc_model="$model_id"

  case "$action" in
    help) _show_help; return 0 ;;
    kill) _kill_server; _kill_tunnel; return 0 ;;
  esac

  _check_deps || return 1

  if [[ "$mode" == "ooz" ]]; then
    # ── OOZ remote endpoint via SSH tunnel ─────────────────────────────
    _start_tunnel || return 1
    # Prefer the pinned OOZ_MODEL (matches opencode.json); else auto-detect.
    oc_model="$ooz_model"
    if [[ -z "$oc_model" ]]; then
      oc_model=$(_discover_ooz_model)
    fi
    if [[ -z "$oc_model" ]]; then
      _err "Could not detect a model from the OOZ endpoint"
      _info "Set ${c_bold}OOZ_MODEL${c_reset} in ai.env, or check ${c_dim}http://127.0.0.1:${ooz_local_port}/v1/models${c_reset}"
      return 1
    fi
    oc_provider="ooz"
    _ok "Remote model: ${c_bold}${oc_model}${c_reset}"
  else
    _reap_orphan_mcps

    # Pull the selected model eagerly so the server never lazy-fails on a
    # missing download (and so `-light`'s first run fetches the 35B-A3B-4bit weights).
    _ensure_model || return 1

    # ── Server management ──────────────────────────────────────────────
    local running_pid
    running_pid=$(_server_pid)

    if [[ -n "$running_pid" ]]; then
      if _server_healthy; then
        local running_model=""
        if [[ -f "$state_file" ]]; then
          IFS= read -r running_model < "$state_file"
        fi
        if [[ "$running_model" != "$model_id" ]]; then
          _warn "Server running with different model (${running_model:-unknown})"
          _info "Switching to ${c_bold}${model_label}${c_reset}"
          _kill_server
          _start_server || return 1
        else
          _ok "Server already running: ${c_bold}${model_label}${c_reset} ${c_dim}(PID ${running_pid})${c_reset}"
        fi
      else
        _warn "Port ${server_port} occupied but server is not healthy"
        _info "Killing stale process ${c_dim}(PID ${running_pid})${c_reset}"
        _kill_server
        _start_server || return 1
      fi
    else
      _start_server || return 1
    fi

    # Detect a lingering opencode on a different model that would force oMLX to
    # hold two big LLMs at once (the server restart above can't stop that client).
    _warn_model_conflict
  fi

  # ── RAG check ──────────────────────────────────────────────────────
  # opencode.json points smart-coding at a private, repo-owned copy of
  # smart-coding-mcp (so we never mutate a shared global package). Its embedder
  # is patched to run on oMLX (bge-m3, Metal) instead of in-process Xenova —
  # re-applied idempotently here so a `npm update` of the copy can't silently
  # revert it. The patch falls back to Xenova if the oMLX env isn't set.
  local sc_omlx_dir="${SMART_CODING_OMLX_DIR:-${HOME}/.smart-coding-omlx}"
  local sc_pkg="${sc_omlx_dir}/node_modules/smart-coding-mcp"
  if [[ -d "$sc_pkg" ]]; then
    if command -v node >/dev/null 2>&1 && [[ -f "${ai_dir}/scripts/patch-smart-coding-omlx.mjs" ]]; then
      node "${ai_dir}/scripts/patch-smart-coding-omlx.mjs" "$sc_pkg" >/dev/null 2>&1
    fi
    _ok "smart-coding-mcp available ${c_dim}(private; embeddings on oMLX bge-m3)${c_reset}"
  else
    _warn "smart-coding-mcp (oMLX) not installed — RAG disabled"
    _info "Install: ${c_dim}npm install --prefix ${sc_omlx_dir} smart-coding-mcp${c_reset}"
  fi

  # ── Memory check (opencode-mem plugin) ─────────────────────────────
  # Persistent cross-session memory: auto-capture summarizer + embeddings run
  # on the local oMLX server, SQLite at ~/.opencode-mem.
  #
  # The summarizer is a raw OpenAI client to oMLX (memoryApiUrl), so it bypasses
  # opencode.json's context limit and would otherwise feed oMLX the full,
  # uncapped turn transcript (~120k tokens observed) — saturating the memory
  # guard, throttling coding turns and 507-ing concurrent bge-m3 loads. We patch
  # its buildMarkdownContext to cap the summarizer input (idempotent; re-applied
  # so a plugin re-download can't revert it). opencode may load either the
  # config-dir install or its plugin cache, so patch both if present.
  if command -v node >/dev/null 2>&1 && [[ -f "${ai_dir}/scripts/patch-opencode-mem-cap.mjs" ]]; then
    for mem_pkg in \
      "${HOME}/.config/opencode/node_modules/opencode-mem" \
      "${HOME}"/.cache/opencode/packages/opencode-mem@*/node_modules/opencode-mem; do
      [[ -d "$mem_pkg" ]] || continue
      node "${ai_dir}/scripts/patch-opencode-mem-cap.mjs" "$mem_pkg" >/dev/null 2>&1
    done
  fi
  if command -v node >/dev/null 2>&1 && [[ -e "${HOME}/.config/opencode/opencode-mem.jsonc" ]]; then
    _ok "opencode-mem active ${c_dim}(local; web UI http://127.0.0.1:4747)${c_reset}"
  else
    _warn "opencode-mem not fully configured"
    [[ -e "${HOME}/.config/opencode/opencode-mem.jsonc" ]] || \
      _info "Symlink config: ${c_dim}ln -sf ${ai_dir}/opencode-mem.jsonc ~/.config/opencode/opencode-mem.jsonc${c_reset}"
    command -v node >/dev/null 2>&1 || _info "node not found — the plugin needs Node/Bun"
  fi

  # ── Post-edit lint/typecheck plugin ────────────────────────────────
  # Deterministic enforcement: opencode's tool.execute.after hook runs ESLint +
  # tsc + Prettier after every edit and *throws* remaining errors back into the
  # agent loop, so the model can't leave broken code behind (prompt-level rules
  # get skipped, especially by the local 35B model). opencode auto-loads any file
  # in ~/.config/opencode/plugins/ at startup (note: directory is plural — the
  # singular "plugin" key in opencode.json is the npm-package array, a different
  # thing). We keep the global symlink current (idempotent — re-pointed on every
  # launch so it can't drift) and clean up the old singular-dir symlink from
  # earlier builds. Auto-skips projects without ESLint/tsconfig/Prettier.
  # NOTE: opencode loads plugins only at startup — restart opencode to pick up
  # changes to this plugin. See plugins/post-edit-check.js.
  local lint_src="${ai_dir}/plugins/post-edit-check.js"
  local lint_dst="${HOME}/.config/opencode/plugins/post-edit-check.js"
  rm -f "${HOME}/.config/opencode/plugin/post-edit-check.js" 2>/dev/null  # old wrong (singular) path
  if [[ -f "$lint_src" ]]; then
    mkdir -p "${HOME}/.config/opencode/plugins"
    ln -sf "$lint_src" "$lint_dst"
    _ok "post-edit-check active ${c_dim}(ESLint + tsc + Prettier enforced on edit)${c_reset}"
  else
    _warn "post-edit-check plugin missing — lint/typecheck not enforced"
  fi

  # ── Launch frontend ──────────────────────────────────────────────────
  echo ""
  cd "$caller_dir" || return 1

  if [[ "$mode" == "cc" ]]; then
    # Experimental: point Claude Code at the local oMLX Anthropic-compatible
    # endpoint (/v1/messages). Claude Code believes it's talking to Anthropic;
    # oMLX serves Qwen. ANTHROPIC_MODEL overrides the requested model id so the
    # request resolves to a model oMLX actually serves.
    _info "Launching ${c_bold}Claude Code${c_reset} → ${c_bold}local oMLX${c_reset} ${c_dim}(experimental)${c_reset}"
    echo ""
    ANTHROPIC_BASE_URL="http://127.0.0.1:${server_port}" \
    ANTHROPIC_API_KEY="omlx" \
    ANTHROPIC_MODEL="$model_id" \
    ANTHROPIC_SMALL_FAST_MODEL="$model_id" \
    claude "${passthrough_args[@]}"
    return $?
  fi

  _info "Launching ${c_bold}opencode${c_reset} with ${c_bold}${oc_provider}/${oc_model}${c_reset}"
  echo ""
  opencode -m "${oc_provider}/${oc_model}" "${passthrough_args[@]}"
  return $?
}

# Allow both sourcing and direct execution
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && ai "$@"
