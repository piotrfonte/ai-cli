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
  # Each profile sets all six: the served id/label/context, plus the oMLX venv it
  # needs, its KV-cache directory and that cache's budget in GB. The last three
  # are per-profile because Muse Glimmer requires a much newer oMLX than the
  # Qwen/Gemma profiles run, and the two versions cannot share a cache directory.
  local model_id model_label model_context_limit
  local model_omlx_venv model_cache_dir model_cache_gb
  local server_port="${AI_PORT:-10081}"
  local state_file="${ai_state_dir}/omlx-model"
  local pid_file="${ai_state_dir}/omlx-server.pid"
  local startup_timeout=120

  # ── oMLX server config (override via environment) ────────────────────
  # oMLX is a native Apple-Silicon inference server with a two-tier KV cache
  # (hot RAM + cold SSD) that restores recurring prefixes from disk instead of
  # recomputing them — the agentic-coding win. Built from source into a venv;
  # see CLAUDE.md for the build steps.
  #
  # Only the profile-independent settings live here. The binary, the KV-cache
  # directory and that cache's budget depend on which model runs, so they are
  # resolved in _resolve_runtime() after the profile dispatch below.
  local omlx_model_dir="${OMLX_MODEL_DIR:-${HOME}/.omlx/models}"
  local omlx_hot_cache="${OMLX_HOT_CACHE:-8GB}"       # in-RAM hot KV tier; model+tier must stay under the guard's soft threshold (85%)
  local omlx_memory_guard_gb="${OMLX_MEMORY_GUARD_GB:-48}"  # ceiling on 64 GB box
  local omlx_max_concurrent="${OMLX_MAX_CONCURRENT:-2}"     # continuous batching: 1 coding turn + 1 opencode-mem summarizer

  # Filled by _resolve_runtime(); every reader runs after the profile dispatch.
  local omlx_bin="" omlx_cache_dir="" omlx_ssd_cache_max="" omlx_cache_prune_gb=""

  # Resolve the per-profile runtime. Environment overrides win over the profile,
  # so a box with one oMLX build can still pin OMLX_BIN / OMLX_CACHE_DIR globally.
  #
  # The profile's own venv is preferred over an `omlx` on PATH: a PATH build is
  # whatever was installed last, and running Muse Glimmer on the older oMLX simply
  # fails (that architecture landed 2190 commits after the pinned build).
  #
  # The two oMLX versions must not share --paged-ssd-cache-dir. Note the reason:
  # it is NOT the cache format. Both builds define _CACHE_FORMAT_VERSION = "3",
  # and the new one writes "3" too unless gdn_ssd_split_enabled (default off) or
  # a PoolingCache delta applies — and a rejected block is only a cache miss.
  # The real reason is mutual eviction: both servers prune their directory
  # oldest-first down to THEIR OWN budget at every start, so one shared directory
  # means each start deletes the other's warm blocks. That destroys the
  # prefix-cache win that collapses agentic time-to-first-token from ~30s to ~1s.
  #
  # oMLX's own LRU governs only the *live* index, so blocks orphaned by prior
  # runs/model-quant switches leak on disk far over the cap (observed: 122 GB vs
  # a 40 GB cap). _prune_cache enforces the budget at each server (re)start —
  # safe because _start_server only runs while no oMLX server is up. The server
  # cap and the prune target come from the same number so they cannot disagree.
  # Set OMLX_CACHE_PRUNE_GB=0 to disable pruning.
  _resolve_runtime() {
    omlx_bin="${OMLX_BIN:-}"
    if [[ -z "$omlx_bin" ]]; then
      if [[ -x "${model_omlx_venv}/bin/omlx" ]]; then
        omlx_bin="${model_omlx_venv}/bin/omlx"
      elif command -v omlx >/dev/null 2>&1; then
        omlx_bin="omlx"
      else
        omlx_bin="${model_omlx_venv}/bin/omlx"   # missing: _check_deps reports this path
      fi
    fi
    omlx_cache_dir="${OMLX_CACHE_DIR:-$model_cache_dir}"
    omlx_ssd_cache_max="${OMLX_SSD_CACHE_MAX:-${model_cache_gb}GB}"
    omlx_cache_prune_gb="${OMLX_CACHE_PRUNE_GB:-${omlx_ssd_cache_max//[!0-9]/}}"
  }

  # ── Model profile ────────────────────────────────────────────────────
  # model_id must match a model oMLX serves from --model-dir (the two-level
  # <namespace>/<name> form is accepted) AND the id keyed in opencode.json.
  # Default: Qwen 3.6 35B-A3B in a flat MLX 6-bit quant (~27.5 GB resident).
  # The everyday coder — broad context (65 k) and no per-model oMLX settings to
  # enable; just works on a fresh box.
  _model_qwen() {
    model_id="mlx-community/Qwen3.6-35B-A3B-6bit"
    model_label="Qwen 3.6 35B-A3B 6-bit"
    model_context_limit=65536
    model_omlx_venv="${HOME}/.omlx/venv"
    model_cache_dir="${HOME}/.omlx/cache"
    model_cache_gb=15
  }

  # Opt-in via -l/--lite: the same A3B model in oMLX's native oQ6 quant
  # (data-driven mixed precision) with MTP heads preserved (-mtp). MTP
  # (multi-token prediction / speculative decode) is OFF by default in oMLX and
  # is enabled per-model via ~/.omlx/model_settings.json — ai.sh writes that key
  # on launch (see scripts/patch-omlx-mtp.mjs). ~30 GB resident; KV is cheap
  # (2 KV heads → ~80 KB/token), so the binding limit is the prefill transient
  # against the Metal working-set cap — 49 k is the empirically safe ceiling
  # (see opencode.json). Faster decode than the flat 6-bit when MTP engages.
  _model_lite() {
    model_id="Jundot/Qwen3.6-35B-A3B-oQ6-mtp"
    model_label="Qwen 3.6 35B-A3B oQ6 +MTP (lite)"
    model_context_limit=49152
    model_omlx_venv="${HOME}/.omlx/venv"
    model_cache_dir="${HOME}/.omlx/cache"
    model_cache_gb=15
  }

  # Opt-in via -g/--gemma: Gemma 4 12B instruct, QAT base + OptiQ
  # mixed-precision 4-bit (329 per-layer overrides, not a flat quant). 9 GB on
  # disk, ~11 GB resident at 65 k — a third of the Qwen default. But it's a
  # DENSE 12B against Qwen's 35B-A3B MoE (~3B active), so every token reads all
  # ~9 GB of weights: expect slower decode despite the smaller footprint. KV is
  # near-free (40 of 48 layers are sliding-window 1024 → ~335 MB fixed; the 8
  # global layers share one K/V tensor → ~8 KB/token ⇒ ~0.9 GB at 65 k), so the
  # 65 k cap matches the default for a clean single-variable comparison rather
  # than tracking any memory limit.
  _model_gemma() {
    model_id="mlx-community/gemma-4-12B-it-qat-OptiQ-4bit"
    model_label="Gemma 4 12B QAT+OptiQ 4-bit"
    model_context_limit=65536
    model_omlx_venv="${HOME}/.omlx/venv"
    model_cache_dir="${HOME}/.omlx/cache"
    model_cache_gb=15
  }

  # Opt-in via --muse: Meta Muse Glimmer 30B in oMLX's native oQ4e quant — a
  # 4-bit floor with per-layer overrides placed by an importance matrix that was
  # calibrated on code, built by the oMLX author with oMLX 0.5.8.dev1. 20.3 GB on
  # disk. This profile is UNPROVEN; it exists to measure, not because it is known
  # to beat Qwen. Three facts govern it:
  #
  #  1. It needs a NEWER oMLX. Muse Glimmer support landed 2190 commits after the
  #     build the other profiles run, so this profile alone uses ~/.omlx/venv-next
  #     (built from ~/.omlx/src-next). The Qwen and Gemma profiles keep the pinned
  #     build untouched, which is what makes a rollback real.
  #  2. It is a DENSE 30B, not a MoE. Every decoded token reads all the weights,
  #     against ~3B active parameters for Qwen 35B-A3B. Expect much slower decode.
  #  3. Long-range recall is structurally weak: only 13 of 52 layers are
  #     full_attention, the other 39 are sliding-window 2048. This is the same
  #     caveat as Gemma (8 of 48, window 1024), but over a longer model.
  #
  # KV is cheap (2 KV heads, ~13 KB/token ⇒ ~0.85 GB at 65 k), so the 65 k cap
  # matches the Qwen default for a clean single-variable comparison rather than
  # tracking any memory limit. The weights carry a vision tower (~0.9 GB) that is
  # never used: oMLX always routes muse_glimmer through the VLM engine and no
  # runtime flag skips it. Accepted as dead weight — see CLAUDE.md.
  _model_muse() {
    model_id="Jundot/Muse-Glimmer-30B-oQ4e"
    model_label="Muse Glimmer 30B oQ4e"
    model_context_limit=65536
    model_omlx_venv="${HOME}/.omlx/venv-next"
    model_cache_dir="${HOME}/.omlx/cache-next"
    model_cache_gb=25
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
  # lingering opencode from a previous `ai`/`ai -l` run keeps requesting its
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
    printf "    ${c_cyan}-l,     --lite${c_reset}        Use the oQ6 +MTP quant ${c_dim}(speculative decode, 49k ctx, no MCPs)${c_reset}\n"
    printf "    ${c_cyan}-g,     --gemma${c_reset}       Use Gemma 4 12B QAT+OptiQ 4-bit ${c_dim}(dense 12B, ~11 GB resident, 65k ctx)${c_reset}\n"
    printf "    ${c_cyan}        --muse${c_reset}        Use Muse Glimmer 30B oQ4e ${c_dim}(dense 30B, newer oMLX, 65k ctx — unproven)${c_reset}\n"
    printf "    ${c_cyan}--no-hybrid${c_reset}          Disable the cloud-Claude ${c_bold}@advisor${c_reset} subagent ${c_dim}(on by default)${c_reset}\n"
    printf "    ${c_cyan}-k,     --kill${c_reset}       Kill the oMLX server\n"
    printf "    ${c_cyan}-h,     --help${c_reset}       Show this help\n"
    echo ""
    printf "  ${c_bold}Model:${c_reset}\n"
    printf "    ${c_dim}Qwen 3.6 35B-A3B 6-bit (local, default)${c_reset}\n"
    printf "    ${c_dim}Qwen 3.6 35B-A3B oQ6 +MTP (local, via -l)${c_reset}\n"
    printf "    ${c_dim}Gemma 4 12B QAT+OptiQ 4-bit (local, via -g)${c_reset}\n"
    printf "    ${c_dim}Muse Glimmer 30B oQ4e (local, via --muse; runs ~/.omlx/venv-next)${c_reset}\n"
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
    _box_line " ${c_dim}one-time download (9–30 GB depending on model) — progress below${c_reset}"
    _box_bottom
    echo ""

    # hf prints the resolved snapshot path to stdout as a "path=<dir>" line (hf 1.x;
    # older CLIs print a bare path). HF_XET_HIGH_PERFORMANCE enables the fast Xet
    # transfer backend (the old HF_HUB_ENABLE_HF_TRANSFER is deprecated in 1.x).
    # NOTE: the Xet backend also writes progress lines ("Fetching N files",
    # "Download complete") to *stdout*, and they can TRAIL the path= line — so a
    # naive `tail -1` grabs a progress line instead of the path (and tqdm uses \r,
    # not \n, between updates). We capture stdout (letting per-file progress on
    # stderr through to the terminal), split on \r, and pull the path= line. If
    # that yields nothing usable we fall back to resolving the snapshot straight
    # from the HF cache layout (refs/main → snapshots/<rev>), which is immune to
    # any output-format drift. Capturing without a pipe also lets `||` see hf's
    # real exit status (a piped `| tail` would mask a download failure).
    local raw
    raw=$(HF_XET_HIGH_PERFORMANCE=1 "$hf_bin" download "$model_id") || {
      _err "Download failed for ${model_id}"
      return 1
    }
    local snapshot
    snapshot=$(printf '%s' "$raw" | tr '\r' '\n' | sed -n 's/^path=//p' | tail -1)
    [[ -n "$snapshot" && -d "$snapshot" ]] || snapshot=$(printf '%s' "$raw" | tr '\r' '\n' | grep -v '=' | tail -1)
    if [[ -z "$snapshot" || ! -d "$snapshot" ]]; then
      # Fallback: deterministic HF cache layout. hf stores repo <ns>/<name> at
      # <hub>/models--<ns>--<name>/snapshots/<rev>, with refs/main holding <rev>.
      local hub="${HF_HUB_CACHE:-${HF_HOME:-${HOME}/.cache/huggingface}/hub}"
      local repo_dir="${hub}/models--${model_id//\//--}"
      local rev=""
      [[ -f "${repo_dir}/refs/main" ]] && IFS= read -r rev < "${repo_dir}/refs/main"
      [[ -n "$rev" ]] && snapshot="${repo_dir}/snapshots/${rev}"
    fi
    if [[ -z "$snapshot" || ! -d "$snapshot" ]]; then
      _err "Download did not yield a snapshot directory"
      return 1
    fi

    mkdir -p "$(dirname "$target")"
    ln -sfn "$snapshot" "$target"
    _ok "Model ready ${c_dim}(${target})${c_reset}"
  }

  # ── Prune the paged SSD KV cache to the cap ────────────────────────────
  # oMLX's LRU eviction only tracks blocks in its *live* index; blocks orphaned
  # by earlier runs or model/quant switches are never revisited, so the on-disk
  # footprint drifts far past --paged-ssd-cache-max-size. Enforce the cap here by
  # deleting oldest-first (mtime = LRU, matching oMLX's own intent) until under
  # target. Only ever called from _start_server with the server down, so no live
  # process holds these blocks; a block is content-addressed, so a later cache
  # lookup for a deleted one is just a miss → recompute (the safe failure mode).
  _prune_cache() {
    local dir=$1 max_gb=$2
    [[ -d "$dir" && -n "$max_gb" && "$max_gb" -gt 0 ]] 2>/dev/null || return 0
    find "$dir" -name '.DS_Store' -type f -delete 2>/dev/null   # Finder cruft
    local max_bytes=$(( max_gb * 1024 * 1024 * 1024 )) cur_bytes
    cur_bytes=$(( $(du -sk "$dir" 2>/dev/null | awk '{print $1+0}') * 1024 ))
    (( cur_bytes > max_bytes )) || return 0
    _info "Pruning KV cache: $(awk -v b="$cur_bytes" 'BEGIN{printf "%.1f", b/1073741824}')GB on disk over ${max_gb}GB cap (oMLX LRU left orphans)"
    local removed=0 reclaimed=0 mtime size path
    while IFS=' ' read -r mtime size path; do
      (( cur_bytes > max_bytes )) || break
      [[ -n "$path" ]] || continue
      if rm -f "$path" 2>/dev/null; then
        cur_bytes=$(( cur_bytes - size )); reclaimed=$(( reclaimed + size )); removed=$(( removed + 1 ))
      fi
    done < <(find "$dir" -type f ! -name '.DS_Store' -exec stat -f '%m %z %N' {} + 2>/dev/null | sort -n)
    _ok "Reclaimed $(awk -v b="$reclaimed" 'BEGIN{printf "%.1f", b/1073741824}')GB from KV cache ${c_dim}(${removed} stale blocks, now ≤${max_gb}GB)${c_reset}"
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
    _box_line " ${c_bold}oMLX:${c_reset}  ${c_dim}${omlx_bin}${c_reset}"
    _box_bottom
    echo ""

    mkdir -p "$(dirname "$state_file")" "$omlx_cache_dir" "$omlx_model_dir"
    _prune_cache "$omlx_cache_dir" "$omlx_cache_prune_gb"
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
        # Line 1: served model id. Line 2: the oMLX binary serving it. The binary
        # matters as much as the model now that profiles run different oMLX
        # builds — the pinned build cannot serve Muse Glimmer at all, so a
        # same-model/different-binary case must still force a restart.
        printf "%s\n%s\n" "$model_id" "$omlx_bin" > "$state_file"
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
    if [[ ! -x "$omlx_bin" ]] && ! command -v omlx >/dev/null 2>&1; then
      # Name the venv this profile expects, and the matching source checkout.
      # --muse needs the second, newer pair; every other profile needs the pinned
      # one. Telling the user to build the wrong one wastes a long build.
      local src_dir="${HOME}/.omlx/src"
      [[ "$model_omlx_venv" == *"-next" ]] && src_dir="${HOME}/.omlx/src-next"
      _err "Missing dependency: ${c_bold}omlx${c_reset} (expected at ${c_dim}${omlx_bin}${c_reset})"
      _info "Build: ${c_dim}git clone https://github.com/jundot/omlx ${src_dir} \\"
      _info "  && uv venv ${model_omlx_venv} --python 3.12 \\"
      _info "  && VIRTUAL_ENV=${model_omlx_venv} uv pip install -e ${src_dir}${c_reset}"
      missing=1
    fi
    # A PATH fallback is fine for the pinned profiles — someone may have oMLX
    # installed outside ~/.omlx/venv. It is NOT fine for --muse: the older build
    # has no muse_glimmer support at all, so the launcher would report success
    # and oMLX would only fail later, at model load, where the cause is far less
    # obvious. Catch it here. An explicit OMLX_BIN is a deliberate choice, so
    # that only warns; an accidental PATH fallback is a hard error.
    if [[ "$profile" == "muse" && "$omlx_bin" != "${model_omlx_venv}/bin/omlx" ]]; then
      if [[ -n "${OMLX_BIN:-}" ]]; then
        _warn "OMLX_BIN points --muse at ${c_dim}${omlx_bin}${c_reset}, not ${c_dim}${model_omlx_venv}/bin/omlx${c_reset}"
        _info "Muse Glimmer needs oMLX ≥0.5.8; the pinned 0.4.2rc1 cannot load it."
      else
        _err "--muse needs the newer oMLX at ${c_dim}${model_omlx_venv}/bin/omlx${c_reset} (resolved: ${c_dim}${omlx_bin}${c_reset})"
        _info "Muse Glimmer support landed 2190 commits after the pinned build — the older one cannot load it."
        _info "Build: ${c_dim}git clone https://github.com/jundot/omlx ${HOME}/.omlx/src-next \\"
        _info "  && uv venv ${model_omlx_venv} --python 3.12 \\"
        _info "  && VIRTUAL_ENV=${model_omlx_venv} uv pip install -e ${HOME}/.omlx/src-next${c_reset}"
        missing=1
      fi
    fi
    return $missing
  }

  # ── Main logic ───────────────────────────────────────────────────────
  local action=""               # "" | "kill" | "help"
  local profile="default"       # "default" (35B-A3B 6-bit) | "lite" (35B-A3B oQ6 +MTP) | "gemma" (Gemma 4 12B QAT+OptiQ) | "muse" (Muse Glimmer 30B oQ4e)
  local hybrid=1                # cloud-Claude @advisor subagent ON by default; disable with --no-hybrid
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
      -l|--lite)
        if [[ "$profile" != "default" && "$profile" != "lite" ]]; then
          _err "Conflicting model flags: --${profile} and $1"
          _show_help
          return 1
        fi
        profile="lite"
        shift
        ;;
      -g|--gemma|-gemma)
        # Model flags are mutually exclusive — picking the wrong one silently
        # costs a multi-GB download or a server restart, so fail loudly.
        if [[ "$profile" != "default" && "$profile" != "gemma" ]]; then
          _err "Conflicting model flags: --${profile} and $1"
          _show_help
          return 1
        fi
        profile="gemma"
        shift
        ;;
      --muse|-muse)
        if [[ "$profile" != "default" && "$profile" != "muse" ]]; then
          _err "Conflicting model flags: --${profile} and $1"
          _show_help
          return 1
        fi
        profile="muse"
        shift
        ;;
      -hybrid|--hybrid)
        hybrid=1
        shift
        ;;
      --no-hybrid|-no-hybrid)
        hybrid=0
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
    lite)  _model_lite ;;
    gemma) _model_gemma ;;
    muse)  _model_muse ;;
    *)     _model_qwen ;;
  esac
  _resolve_runtime
  local oc_model="$model_id"

  case "$action" in
    help) _show_help; return 0 ;;
    kill) _kill_server; return 0 ;;
  esac

  _check_deps || return 1

  _reap_orphan_mcps

  # Pull the selected model eagerly so the server never lazy-fails on a
  # missing download (a first `ai` fetches the 6-bit default; a first `ai -l`
  # fetches the oQ6-mtp weights; a first `ai -g` fetches Gemma 4 12B; a first
  # `ai --muse` fetches the 20.3 GB Muse Glimmer oQ4e weights).
  _ensure_model || return 1

  # Enable per-model oMLX settings that aren't server CLI flags: MTP
  # (multi-token prediction) for the oQ6-mtp (`-l`) build. These live in
  # ~/.omlx/model_settings.json, which oMLX reads at model
  # load — so a running server must be restarted to pick up a change (the
  # model-switch restart below handles the common case). Idempotent merge: it
  # only writes when a value differs, and never clobbers other models/keys.
  local omlx_base_dir="${OMLX_BASE_DIR:-${HOME}/.omlx}"
  if command -v node >/dev/null 2>&1 && [[ -f "${ai_dir}/scripts/patch-omlx-mtp.mjs" ]]; then
    node "${ai_dir}/scripts/patch-omlx-mtp.mjs" "${omlx_base_dir}/model_settings.json" >/dev/null 2>&1
  fi

  # ── Server management ──────────────────────────────────────────────
  local running_pid
  running_pid=$(_server_pid)

  if [[ -n "$running_pid" ]]; then
    if _server_healthy; then
      local running_model="" running_bin=""
      if [[ -f "$state_file" ]]; then
        { IFS= read -r running_model; IFS= read -r running_bin; } < "$state_file" 2>/dev/null
      fi
      if [[ "$running_model" != "$model_id" ]]; then
        _warn "Server running with different model (${running_model:-unknown})"
        _info "Switching to ${c_bold}${model_label}${c_reset}"
        _kill_server
        _start_server || return 1
      elif [[ "$running_bin" != "$omlx_bin" ]]; then
        # Same model, different oMLX build — or a state file written before the
        # binary was recorded, where we cannot tell. Restart either way: the
        # profiles now run oMLX versions 2190 commits apart, and guessing wrong
        # means serving a model the running build does not implement.
        _warn "Server running from a different oMLX build (${running_bin:-unrecorded})"
        _info "Restarting on ${c_dim}${omlx_bin}${c_reset}"
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

  # ── MCP / RAG ──────────────────────────────────────────────────────
  # Lite runs MCP-free. opencode deep-merges OPENCODE_CONFIG_CONTENT over the
  # global opencode.json (later wins), so emitting {enabled:false} for every MCP
  # server declared there disables them all for this session only — no edit to
  # opencode.json, and new servers added later are covered automatically. Passed
  # to the opencode launch below; an empty value is ignored by opencode.
  local oc_config_content=""
  if [[ "$profile" == "lite" ]]; then
    if command -v node >/dev/null 2>&1 && [[ -f "${ai_dir}/opencode.json" ]]; then
      oc_config_content=$(node -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const m={};for(const k of Object.keys(c.mcp||{}))m[k]={enabled:false};process.stdout.write(JSON.stringify({$schema:"https://opencode.ai/config.json",mcp:m}));' "${ai_dir}/opencode.json" 2>/dev/null)
    fi
    _info "MCPs disabled ${c_dim}(lite — no smart-coding RAG / chrome-devtools)${c_reset}"
  else
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
      # Keep third-party trees out of the index. smart-coding-mcp builds its final
      # exclude list from ProjectDetector alone (its own DEFAULT_CONFIG list is
      # discarded, and in --workspace mode the package config.json is never read),
      # and the detector only emits a language's ignore patterns when it detects
      # that language — while "py" is unconditionally indexable. So a JS repo with
      # a stray .venv indexes the whole virtualenv: measured 4,348 of 5,115 files
      # and 94.5% of all chunks on one client repo, which pinned oMLX at >100% CPU
      # for hours embedding library source one HTTP request per chunk. The patch
      # adds a SMART_CODING_EXCLUDE_PATTERNS override applied last in loadConfig();
      # its built-in virtualenv set needs no configuration. Idempotent.
      if command -v node >/dev/null 2>&1 && [[ -f "${ai_dir}/scripts/patch-smart-coding-excludes.mjs" ]]; then
        node "${ai_dir}/scripts/patch-smart-coding-excludes.mjs" "$sc_pkg" >/dev/null 2>&1
      fi
      # Exported (not set in opencode.json) so they can be tuned per-box from ai.env;
      # opencode merges its MCP `environment` block over the inherited env, so leaving
      # these unset simply keeps the patch's built-in virtualenv defaults in force.
      if [[ -n "${SMART_CODING_EXCLUDE_PATTERNS:-}" ]]; then
        export SMART_CODING_EXCLUDE_PATTERNS
      fi
      if [[ -n "${SMART_CODING_EXCLUDE_DEFAULTS:-}" ]]; then
        export SMART_CODING_EXCLUDE_DEFAULTS
      fi
      _ok "smart-coding-mcp available ${c_dim}(private; embeddings on oMLX bge-m3)${c_reset}"
    else
      _warn "smart-coding-mcp (oMLX) not installed — RAG disabled"
      _info "Install: ${c_dim}npm install --prefix ${sc_omlx_dir} smart-coding-mcp${c_reset}"
    fi
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
      # Directory-exclude: skip capture/recall in OPENCODE_MEM_EXCLUDE_DIRS trees
      # (any sensitive client repos). See the patch script — opencode-mem has no
      # native directory-scoped opt-out, so we patch one in.
      [[ -f "${ai_dir}/scripts/patch-opencode-mem-exclude.mjs" ]] && \
        node "${ai_dir}/scripts/patch-opencode-mem-exclude.mjs" "$mem_pkg" >/dev/null 2>&1
      # Model override: let OPENCODE_MEM_MODEL (set at launch to the session model)
      # steer the summarizer, so it reuses the already-loaded model instead of pulling
      # in the default 35B alongside a -m/-l session and thrashing the memory guard.
      [[ -f "${ai_dir}/scripts/patch-opencode-mem-model.mjs" ]] && \
        node "${ai_dir}/scripts/patch-opencode-mem-model.mjs" "$mem_pkg" >/dev/null 2>&1
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

  # ── Hybrid cloud advisor (on by default; --no-hybrid to disable) ───────────
  # A read-only, prompt-only cloud-Claude subagent the local model never auto-
  # calls — you summon it by hand with @advisor (see agents/advisor.md). It is
  # enabled by default (default/-l/-m); --no-hybrid turns it off.
  # Three independent privacy controls:
  #   1. GATING — the agent file is symlinked in ONLY when hybrid is active;
  #      otherwise it is removed, so a --no-hybrid launch has no
  #      agent referencing the anthropic provider and thus no egress path at all.
  #      We remove it on every non-hybrid launch so a stale symlink can't silently
  #      re-open the cloud path.
  #   2. MANUAL — opencode.json sets permission.task:"ask", so even if the local
  #      model tries to delegate to the advisor, opencode prompts before anything
  #      leaves the box. The advisor is mode:subagent (never the primary).
  #   3. PROMPT-ONLY — advisor.md denies every tool, so the advisor can only reason
  #      about the text you hand it; it can't open files to widen the egress.
  # Every advisor call is recorded by plugins/advisor-egress-log.js to
  # logs/advisor-egress.jsonl (named .jsonl so the logs/*.log prune can't delete
  # the audit trail). The advisor runs on REAL cloud Claude via opencode's built-in
  # anthropic provider + your `opencode auth login` OAuth.
  local advisor_src="${ai_dir}/agents/advisor.md"
  local advisor_dst="${HOME}/.config/opencode/agents/advisor.md"
  local egress_src="${ai_dir}/plugins/advisor-egress-log.js"
  local egress_dst="${HOME}/.config/opencode/plugins/advisor-egress-log.js"
  local advisor_egress_log=""
  if [[ "$hybrid" == "1" ]]; then
    if [[ -f "$advisor_src" && -f "$egress_src" ]]; then
      mkdir -p "${HOME}/.config/opencode/agents" "${HOME}/.config/opencode/plugins" "$ai_log_dir"
      ln -sf "$advisor_src" "$advisor_dst"
      ln -sf "$egress_src" "$egress_dst"
      advisor_egress_log="${ai_log_dir}/advisor-egress.jsonl"
      # OAuth preflight — warn (don't block) if Anthropic isn't logged in; the
      # advisor will just error until `opencode auth login` is run once.
      if ! grep -q '"anthropic"' "${HOME}/.local/share/opencode/auth.json" 2>/dev/null; then
        _warn "Anthropic OAuth not found — @advisor will fail until you log in"
        _info "Run once: ${c_dim}opencode auth login${c_reset} → Anthropic (uses your Claude plan, no API key)"
      fi
      _ok "@advisor enabled ${c_dim}(cloud Opus, manual + prompt-only; egress → ${advisor_egress_log})${c_reset}"
    else
      _warn "-hybrid requested but advisor files missing — advisor not enabled"
      rm -f "$advisor_dst" "$egress_dst" 2>/dev/null
    fi
  else
    # Airgap guarantee: ensure no advisor/egress plumbing lingers from a prior
    # -hybrid run, so a plain `ai` provably has no path to the cloud.
    rm -f "$advisor_dst" "$egress_dst" 2>/dev/null
  fi

  # Clean up scraps from the removed AFK experiment (agents, loop plugin and the
  # /lock command), so a stale symlink or leftover file can never re-introduce an
  # auto-driving agent into a normal session. Safe on every launch.
  rm -f "${HOME}/.config/opencode/agents/afk.md" \
        "${HOME}/.config/opencode/agents/afk-impl.md" \
        "${HOME}/.config/opencode/agents/afk-planner.md" \
        "${HOME}/.config/opencode/agents/afk-cagetest.md" \
        "${HOME}/.config/opencode/agents/grill.md" \
        "${HOME}/.config/opencode/plugins/afk-loop.js" \
        "${HOME}/.config/opencode/command/lock.md" \
        "${HOME}/.config/opencode/command/afk.md" \
        "${HOME}/.config/opencode/command/afk-issue.md" 2>/dev/null

  # ── Launch frontend ──────────────────────────────────────────────────
  echo ""
  cd "$caller_dir" || return 1

  _info "Launching ${c_bold}opencode${c_reset} with ${c_bold}${oc_provider}/${oc_model}${c_reset}"
  echo ""
  # ADVISOR_EGRESS_LOG is empty unless -hybrid enabled the advisor; the egress-log
  # plugin (only symlinked under -hybrid) reads it to record what's sent to @advisor.
  # OPENCODE_MEM_EXCLUDE_DIRS: never capture/recall memory from these trees. Prepend
  # sensitive client-repo roots via ai.env; read by the patched opencode-mem
  # (patch-opencode-mem-exclude.mjs).
  # OPENCODE_MEM_MODEL points the opencode-mem summarizer at the SAME model this
  # session runs (read by the patched config.js), so auto-capture never loads a second
  # ~20-28GB model alongside -l and thrashes the memory guard into a 507 loop.
  # OPENCODE_CONFIG_CONTENT is an inline config opencode deep-merges last; under -l it
  # carries {enabled:false} for every MCP server (built above), and is empty otherwise
  # (empty = ignored by opencode, so the default keeps its MCPs).
  #
  # The explicit `-m mlx/<id>` is what makes `ai` local regardless of opencode.json's
  # default model (now a Vercel AI Gateway model, for bare `opencode` sessions): the
  # CLI flag wins over the config, so every ai/-l/-g launch pins its own local model.
  ADVISOR_EGRESS_LOG="$advisor_egress_log" \
  OPENCODE_MEM_EXCLUDE_DIRS="${OPENCODE_MEM_EXCLUDE_DIRS:-}" \
  OPENCODE_MEM_MODEL="$model_id" \
  OPENCODE_CONFIG_CONTENT="$oc_config_content" \
  opencode -m "${oc_provider}/${oc_model}" "${passthrough_args[@]}"
  return $?
}

# Allow both sourcing and direct execution
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && ai "$@"
