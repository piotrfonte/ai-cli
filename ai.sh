#!/usr/bin/env bash
# ai.sh — MLX Inference Server Launcher for OpenCode
# Usage: bash ai.sh [OPTIONS] [-- opencode-args...]
#   or:  source ai.sh && ai [OPTIONS] [-- opencode-args...]

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
  local model_id model_label model_max_tokens model_cache_limit
  local model_prompt_cache model_prompt_cache_size model_context_limit
  local server_port="${AI_PORT:-10080}"
  local state_file="${ai_state_dir}/mlx-lm-model"
  local pid_file="${ai_state_dir}/mlx-lm-server.pid"
  local startup_timeout=120

  # ── Model profiles ───────────────────────────────────────────────────
  _model_glm() {
    model_id="mlx-community/GLM-4.7-Flash-6bit"
    model_label="GLM-4.7 Flash 6-bit"
    model_max_tokens=16384
    model_cache_limit=34359738368       # 32 GB Metal cache cap (safe on 64 GB)
    model_prompt_cache=15032385536      # 14 GB KV / prefix cache
    model_prompt_cache_size=1
    model_context_limit=65536
  }

  _model_qwen() {
    model_id="mlx-community/Qwen3.6-35B-A3B-6bit"
    model_label="Qwen 3.6 35B-A3B 6-bit"
    model_max_tokens=16384
    model_cache_limit=34359738368       # 32 GB Metal cache cap (safe on 64 GB)
    model_prompt_cache=15032385536      # 14 GB KV / prefix cache
    model_prompt_cache_size=1
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
        if [[ "$cmd_name" == *python* || "$cmd_name" == *mlx* ]]; then
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
          if [[ "$cmd_name" == *python* || "$cmd_name" == *mlx* ]]; then
            kill -9 "$pid" 2>/dev/null
          fi
        done
      fi
      _ok "Server stopped"
    else
      _info "No server running on port ${server_port}"
    fi
  }

  # ── Show help ────────────────────────────────────────────────────────
  _show_help() {
    echo ""
    _box_top
    _box_line " ${c_bold}ai.sh${c_reset} — Local Inference Launcher"
    _box_bottom
    echo ""
    printf "  ${c_bold}Usage:${c_reset}  ai.sh [OPTIONS] [-- opencode-args...]\n"
    echo ""
    printf "  ${c_bold}Options:${c_reset}\n"
    printf "    ${c_cyan}-glm, --glm${c_reset}          Use GLM-4.7 Flash 6-bit\n"
    printf "    ${c_cyan}-k, --kill${c_reset}           Kill the MLX server\n"
    printf "    ${c_cyan}-h, --help${c_reset}           Show this help\n"
    echo ""
    printf "  ${c_bold}Model:${c_reset}\n"
    printf "    ${c_dim}default${c_reset}              Qwen 3.6 35B-A3B 6-bit\n"
    printf "    ${c_dim}-glm${c_reset}                 GLM-4.7 Flash 6-bit\n"
    echo ""
  }

  # ── Start inference server ────────────────────────────────────────────
  _start_server() {
    echo ""
    _box_top
    _box_line " ${c_bold}Starting mlx-lm Server${c_reset}"
    _box_mid
    _box_line " ${c_bold}Model:${c_reset} ${model_label}"
    _box_line " ${c_dim}${model_id}${c_reset}"
    _box_line " ${c_bold}Port:${c_reset}  ${server_port}"
    _box_bottom
    echo ""

    mkdir -p "$(dirname "$state_file")"
    local log_dir="${ai_log_dir}"
    mkdir -p "$log_dir"
    local server_log="${log_dir}/mlx-lm-server-$(date +%Y%m%d-%H%M%S).log"

    MLX_CACHE_LIMIT="$model_cache_limit" \
    uv run --no-project --with mlx-lm mlx_lm.server \
      --model "$model_id" \
      --port "$server_port" \
      --max-tokens "$model_max_tokens" \
      --temp 0.2 \
      --top-p 1.0 \
      --prefill-step-size 8192 \
      --prompt-cache-bytes "$model_prompt_cache" \
      --prompt-cache-size "$model_prompt_cache_size" \
      --decode-concurrency 1 \
      --prompt-concurrency 1 \
      --pipeline \
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

  # ── Dependency checks ────────────────────────────────────────────────
  _check_deps() {
    local missing=0
    if ! command -v uv >/dev/null 2>&1; then
      _err "Missing dependency: ${c_bold}uv${c_reset}"
      _info "Install: ${c_dim}curl -LsSf https://astral.sh/uv/install.sh | sh${c_reset}"
      missing=1
    fi
    if ! command -v opencode >/dev/null 2>&1; then
      _err "Missing dependency: ${c_bold}opencode${c_reset}"
      _info "Install: ${c_dim}go install github.com/opencode-ai/opencode@latest${c_reset}"
      missing=1
    fi
    return $missing
  }

  # ── Main logic ───────────────────────────────────────────────────────
  local action=""
  local -a passthrough_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -k|--kill)
        action="kill"
        shift
        ;;
      -glm|--glm)
        action="glm"
        shift
        ;;
      -h|--help)
        action="help"
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

  # ── Select model profile ─────────────────────────────────────────────
  case "$action" in
    glm) _model_glm ;;
    *)   _model_qwen ;;
  esac
  local oc_model="$model_id"

  case "$action" in
    help) _show_help; return 0 ;;
    kill) _kill_server; return 0 ;;
  esac

  _check_deps || return 1

  # ── Server management ────────────────────────────────────────────────
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

  # ── RAG check ──────────────────────────────────────────────────────
  if command -v smart-coding-mcp >/dev/null 2>&1; then
    _ok "smart-coding-mcp available ${c_dim}(auto-indexes on connect)${c_reset}"
  else
    _warn "smart-coding-mcp not found — RAG disabled"
    _info "Install: ${c_dim}npm install -g smart-coding-mcp${c_reset}"
  fi

  # ── Launch opencode ──────────────────────────────────────────────────
  echo ""
  _info "Launching ${c_bold}opencode${c_reset} with ${c_bold}${oc_provider}/${oc_model}${c_reset}"
  echo ""

  cd "$caller_dir" || return 1
  opencode -m "${oc_provider}/${oc_model}" "${passthrough_args[@]}"
  return $?
}

# Allow both sourcing and direct execution
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && ai "$@"
