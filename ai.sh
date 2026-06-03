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
  local model_id model_label model_max_tokens model_cache_limit
  local model_prompt_cache model_prompt_cache_size model_context_limit
  local server_port="${AI_PORT:-10081}"
  local state_file="${ai_state_dir}/mlx-lm-model"
  local pid_file="${ai_state_dir}/mlx-lm-server.pid"
  local startup_timeout=120

  # ── OOZ remote endpoint config (used by -ooz; set in ai.env) ─────────
  local ooz_ssh_host="${OOZ_SSH_HOST:-}"
  local ooz_ssh_user="${OOZ_SSH_USER:-}"
  local ooz_ssh_port="${OOZ_SSH_PORT:-22}"
  local ooz_local_port="${OOZ_LOCAL_PORT:-8089}"
  local ooz_remote="${OOZ_REMOTE:-127.0.0.1:8080}"
  local ooz_model="${OOZ_MODEL:-}"   # pin model id; empty → auto-detect

  # ── Model profile ────────────────────────────────────────────────────
  _model_qwen() {
    model_id="mlx-community/Qwen3.6-35B-A3B-6bit"
    model_label="Qwen 3.6 35B-A3B 6-bit"
    model_max_tokens=8192
    model_cache_limit=28991029248       # 27 GB Metal cache cap
    model_prompt_cache=8589934592       # 8 GB KV / prefix cache
    model_prompt_cache_size=2
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
    printf "    ${c_cyan}-ooz, --ooz${c_reset}          Tunnel to the OOZ remote endpoint\n"
    printf "    ${c_cyan}-k,   --kill${c_reset}         Kill the MLX server and OOZ tunnel\n"
    printf "    ${c_cyan}-h,   --help${c_reset}         Show this help\n"
    echo ""
    printf "  ${c_bold}Model:${c_reset}\n"
    printf "    ${c_dim}Qwen 3.6 35B-A3B 6-bit (local)${c_reset}\n"
    printf "    ${c_dim}remote model via -ooz (auto-detected)${c_reset}\n"
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
    find "$log_dir" -maxdepth 1 -type f -name '*.log' -mtime +14 -delete 2>/dev/null
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
    if ! command -v opencode >/dev/null 2>&1; then
      _err "Missing dependency: ${c_bold}opencode${c_reset}"
      _info "Install: ${c_dim}go install github.com/opencode-ai/opencode@latest${c_reset}"
      missing=1
    fi
    if [[ "$mode" == "ooz" ]]; then
      if ! command -v ssh >/dev/null 2>&1; then
        _err "Missing dependency: ${c_bold}ssh${c_reset}"
        missing=1
      fi
    elif ! command -v uv >/dev/null 2>&1; then
      _err "Missing dependency: ${c_bold}uv${c_reset}"
      _info "Install: ${c_dim}curl -LsSf https://astral.sh/uv/install.sh | sh${c_reset}"
      missing=1
    fi
    return $missing
  }

  # ── Main logic ───────────────────────────────────────────────────────
  local action=""               # "" | "kill" | "help"
  local mode="local"            # "local" | "ooz"
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
  _model_qwen
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
  fi

  # ── RAG check ──────────────────────────────────────────────────────
  if command -v smart-coding-mcp >/dev/null 2>&1; then
    _ok "smart-coding-mcp available ${c_dim}(auto-indexes on connect)${c_reset}"
  else
    _warn "smart-coding-mcp not found — RAG disabled"
    _info "Install: ${c_dim}npm install -g smart-coding-mcp${c_reset}"
  fi

  # ── Memory check (opencode-mem plugin) ─────────────────────────────
  # Persistent cross-session memory: auto-capture summarizer runs on the
  # local MLX server, embeddings in-process, SQLite at ~/.opencode-mem.
  if command -v node >/dev/null 2>&1 && [[ -e "${HOME}/.config/opencode/opencode-mem.jsonc" ]]; then
    _ok "opencode-mem active ${c_dim}(local; web UI http://127.0.0.1:4747)${c_reset}"
  else
    _warn "opencode-mem not fully configured"
    [[ -e "${HOME}/.config/opencode/opencode-mem.jsonc" ]] || \
      _info "Symlink config: ${c_dim}ln -sf ${ai_dir}/opencode-mem.jsonc ~/.config/opencode/opencode-mem.jsonc${c_reset}"
    command -v node >/dev/null 2>&1 || _info "node not found — the plugin needs Node/Bun"
  fi

  # ── Launch frontend ──────────────────────────────────────────────────
  echo ""
  cd "$caller_dir" || return 1

  _info "Launching ${c_bold}opencode${c_reset} with ${c_bold}${oc_provider}/${oc_model}${c_reset}"
  echo ""
  opencode -m "${oc_provider}/${oc_model}" "${passthrough_args[@]}"
  return $?
}

# Allow both sourcing and direct execution
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && ai "$@"
