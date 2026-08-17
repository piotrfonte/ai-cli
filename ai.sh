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
  # A profile is one model this launcher serves: a served id and a label for the
  # UI. The context window is NOT set here — opencode.json owns it, so the two
  # numbers can never disagree.
  local model_id model_label
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
  # One build serves every profile, so the binary, the KV-cache directory and its
  # budget no longer vary by model. _resolve_runtime() still resolves them in one
  # place, because the environment may override each of them.
  local omlx_venv="${OMLX_VENV:-${HOME}/.omlx/venv}"
  local omlx_src_dir="${OMLX_SRC_DIR:-${HOME}/.omlx/src}"
  local omlx_model_dir="${OMLX_MODEL_DIR:-${HOME}/.omlx/models}"
  # LM Studio's weight store, and the only copy of any model's weights. LM Studio
  # writes flat <org>/<repo> directories here — NOT Hugging Face's
  # models--<org>--<repo>/snapshots/<sha> layout — and oMLX reaches them through a
  # symlink under $omlx_model_dir. See _ensure_model.
  local hf_hub_dir="${HF_HUB_CACHE:-${HF_HOME:-${HOME}/.cache/huggingface}/hub}"
  local omlx_hot_cache="${OMLX_HOT_CACHE:-8GB}"       # in-RAM hot KV tier; model+tier must stay under the guard's soft threshold (85%)
  local omlx_memory_guard_gb="${OMLX_MEMORY_GUARD_GB:-48}"  # ceiling on 64 GB box
  local omlx_max_concurrent="${OMLX_MAX_CONCURRENT:-2}"     # continuous batching: 1 coding turn + 1 opencode-mem summarizer

  # Prompt-prefix warm-up. OFF by default — it lost a measurement. See _warm_prefix.
  local warm_prefix="${AI_WARM_PREFIX:-0}"          # 1 enables it; only pays if you do not type straight away
  local warm_mcp="${AI_WARM_PREFIX_MCP:-1}"         # 0 drops MCP from the warm-up, which makes it actively harmful
  local warm_log="${ai_log_dir}/prefix-warm.log"

  # Filled by _resolve_runtime(); every reader runs after it.
  local omlx_bin="" omlx_build="" omlx_cache_dir="" omlx_ssd_cache_max="" omlx_cache_prune_gb=""

  # Resolve the runtime. Environment overrides win, so a box with a second oMLX
  # checkout can pin OMLX_BIN / OMLX_CACHE_DIR without touching this file.
  #
  # The venv build is preferred over an `omlx` on PATH: a PATH build is whatever
  # was installed last, so it may not be the one this launcher expects.
  #
  # omlx_build is the value the state file compares to decide whether a running
  # server must restart. The binary PATH alone cannot see an in-place upgrade —
  # the path is identical before and after — so the source checkout's git HEAD
  # carries the signal: the venv install is editable, so that commit IS the code
  # being served. An unresolvable HEAD reads as "unknown", which is stable and
  # therefore never forces a spurious restart.
  #
  # 25GB is the cache budget oMLX enforces, NOT a guard against oMLX. It was
  # sized against unbounded drift (observed: 122 GB vs a 40 GB cap) on a build
  # older than 2026-06-19; upstream 28fe5cb8 (#1915) closed that, and W13 kept
  # the number for want of a measurement either way. _prune_cache stays as a
  # backstop for the one orphan oMLX still cannot see — see its own comment.
  # It runs at each server (re)start, safe because _start_server only runs while
  # no oMLX server is up. The server cap and the prune target come from the same
  # number so they cannot disagree. Set OMLX_CACHE_PRUNE_GB=0 to disable pruning.
  _resolve_runtime() {
    omlx_bin="${OMLX_BIN:-}"
    if [[ -z "$omlx_bin" ]]; then
      if [[ -x "${omlx_venv}/bin/omlx" ]]; then
        omlx_bin="${omlx_venv}/bin/omlx"
      elif command -v omlx >/dev/null 2>&1; then
        omlx_bin="omlx"
      else
        omlx_bin="${omlx_venv}/bin/omlx"   # missing: _check_deps reports this path
      fi
    fi
    local rev=""
    rev=$(git -C "$omlx_src_dir" rev-parse --short HEAD 2>/dev/null)
    omlx_build="${omlx_bin}@${rev:-unknown}"
    omlx_cache_dir="${OMLX_CACHE_DIR:-${HOME}/.omlx/cache}"
    omlx_ssd_cache_max="${OMLX_SSD_CACHE_MAX:-25GB}"
    omlx_cache_prune_gb="${OMLX_CACHE_PRUNE_GB:-${omlx_ssd_cache_max//[!0-9]/}}"
  }

  # ── Model profiles ───────────────────────────────────────────────────
  # Four models, and no others. Every model_id is the two-level <org>/<repo>
  # form: it is the directory this launcher symlinks under --model-dir, the id
  # opencode.json declares, and the id opencode sends. oMLX resolves it to the
  # directory LEAF (resolve_model_id strips everything before the first "/"), so
  # the leaf is what ~/.omlx/model_settings.json must be keyed by.
  #
  # CAPABILITY IS MEASURED, AND IT INVERTS THE SPEED ORDER. Each model passed a
  # serve check — finish_reason stop, non-empty content, reasoning split out, a
  # tool call that parses — which proves only that the model runs. W14 then ran
  # four multi-turn coding tasks, 3 repeats each, graded by EXECUTING the model's
  # own output: Muse 9/12 pass@1, GLM 6/12, Bonsai 5/12. The slowest model on the
  # roster writes the best code and the fastest writes the worst.
  #
  # THAT RANKING IS A SHORT-PROMPT RESULT, and it dissolves at the context an
  # agent turn actually holds. W21 re-ran the three separating tasks at ~17.6k:
  # 9/6/5 pass@1 becomes 8/6/7, Muse and Bonsai TIE at 8/9 on pass@≤2, and every
  # remaining gap sits inside the noise band. Bonsai is then the cheapest per
  # solved task — 2.31 min against Muse's 3.19 — and degrades least with length
  # (1.12x against Muse's 1.39x and GLM's 1.73x).
  #
  # THE DEFAULT IS BONSAI, by the user's decision on 2026-08-14. It is NOT a
  # measured capability lead: at short prompts Muse still leads 9/12 to 5/12, and
  # W18's pre-registered floor — a challenger must lead by three — is not met. It
  # is a choice of the cheapest profile at agentic length and less than half the
  # resident footprint, taken where the evidence no longer separates the models.
  # Muse keeps its short-prompt lead one flag away, at --muse.
  #
  # Measured on prompts under 4,000 tokens (W14) and at ~17.6k (W21, three tasks,
  # 9 runs each). Neither measures capability near a full context window.
  #
  # The numbers below are measured on this box (M4 Max, 64 GB), not estimated.
  # "Door charge" is the cold prefill of a ~12.8k-token agentic prompt, paid once
  # per directory visit; later turns in the same conversation prefill only their
  # fresh tokens, because the paged cache matches the growing prefix.

  # Opt-in via --glm. GLM 4.7 Flash, a 47-layer MoE (64 routed experts, 4 active
  # + 1 shared) with MLA attention: 22.89 GB resident, ~590 tok/s prefill (door
  # charge ~21.8 s), ~68 tok/s decode. It prefills ~3x faster than anything else
  # here, which is what this profile buys.
  #
  # IT WAS THE DEFAULT UNTIL W18, and lost it on measurement. It scored 6/12
  # pass@1, recovered from a real error message 0 times in 12 runs, and ran to
  # finish_reason: length on 4 of 12 turns — a runaway spends the whole
  # 8,192-token budget and returns nothing. This repo's post-edit-check throws
  # errors back at the model, so a model that cannot act on one is weak exactly
  # where this box needs it. Its template accepts enable_thinking, so a pin may
  # cure the runaways and win the default back — that is W19 on the map.
  #
  # It carries an MTP head (num_nextn_predict_layers: 1) that stays OFF: nothing
  # has measured it here, and mtp_enabled is a per-model oMLX setting, not a flag.
  # Its context is capped well under the native 202,752 window because oMLX sizes
  # MLA KV with the MHA formula and over-charges this model ~7x — opencode.json
  # holds the number.
  _model_glm() {
    model_id="lmstudio-community/GLM-4.7-Flash-MLX-6bit"
    model_label="GLM 4.7 Flash 6-bit"
  }

  # Default, also selectable as --bonsai. Ternary Bonsai 27B, a 2-bit ternary
  # fine-tune of Qwen3.6-27B by prism-ml: 8.44 GB resident — less than half of
  # --muse — so it leaves the most room for the hot cache, a summarizer capture
  # and the OS. It costs prefill: ~194 tok/s, so the door charge on a 12.8k
  # prompt is 58.6 s against GLM's 21.8 s. Decode ~38 tok/s short; at 17-22k the
  # figure recorded here was ~12.5 and DOES NOT REPRODUCE — an isolated probe read
  # 25.0 at 20k and a real 1.7-hour suite read 18.8-20.4 end-to-end (a lower bound,
  # since end-to-end includes prefill). Budget 19-25, and say which lane you mean.
  #
  # It scored 5/12 pass@1 but 8/12 with one repair turn — the best recovery rate
  # of the three, so it takes feedback well, which is exactly what this repo's
  # post-edit-check demands of a model. Its 2-bit quant shows no collapse; its
  # failures are ordinary mistakes. At ~17.6k it reaches 7/9, ties Muse on
  # pass@≤2, and costs 2.31 min per solved task against Muse's 3.19 — the
  # cheapest of the three at agentic length, which is what won it the default.
  #
  # It is a VLM with language_model_only: False, so the vision tower loads either
  # way (~0.90 GB); this launcher serves it as a coding model only. 64 layers run
  # 3 linear : 1 full attention, so only 16 layers cache KV — but oMLX does not
  # honour the card's 4-bit KV claim, so KV is fp16 at ~64 KB/token (~4.0 GB at
  # 65 k). It reaches its full declared window with no warning.
  _model_bonsai() {
    model_id="prism-ml/Ternary-Bonsai-27B-mlx-2bit"
    model_label="Ternary Bonsai 27B 2-bit"
  }

  # Opt-in via --muse. Muse Glimmer 30B in a flat 4-bit quant: 18.59 GB resident,
  # ~190 tok/s prefill (door charge 64.5 s), ~26 tok/s decode short and ~11 at
  # 17-22k — the slowest decode on the roster. It wastes almost nothing: 9/12
  # pass@1, 11/12 with one repair, and zero runaways in 12 runs, all at short
  # prompts. Reach for it when the work is short-prompt and hard.
  #
  # W18 made it the default on that short-prompt lead, and it held that until
  # 2026-08-14. W21 then found the lead gone at ~17.6k (8/9 against Bonsai's 7/9,
  # tied on pass@≤2) while the costs stayed: 2.2x the resident footprint and 3.19
  # min per solved task against 2.31. The door charge is paid once per directory
  # visit, so the 64.5 s buys a session, but decode never amortises.
  #
  # A VLM whose perception encoder is ~3.63 GB of the download; served as a coding
  # model only. Its KV is the cheapest of the three — 3 sliding : 1 full attention
  # at a 2048 window means only 13 of 52 layers cache KV (~13 KB/token, ~1.0 GB at
  # 65 k), so it writes nothing to the SSD tier at these sizes. The same 13 layers
  # are the only ones that see the whole window, so long-range recall is weaker
  # than 52 layers suggests. Native window 131,072 — the shortest here.
  _model_muse() {
    model_id="mlx-community/Muse-Glimmer-30B-4bit"
    model_label="Muse Glimmer 30B 4-bit"
  }

  # Opt-in via --qwen. THIS FLAG NAMES A SLOT, NOT A MODEL: the newest Qwen fills
  # it, and a later Qwen (a 3.9, say) REPLACES this model under the SAME flag. It
  # does not get a flag of its own. This roster has moved a model under a flag
  # twice already, and each move needed a rule it did not have.
  #
  # WHY THIS PROFILE EXISTS: it prices Bonsai's 2-bit ternary quant. Qwen3.8-27B
  # is Bonsai's architecture at 4 bits — same qwen3_5 model_type, same 64 layers
  # with 16 caching KV, same head_dim 256 and 4 KV heads (~64 KB/token), same
  # 262,144 native window, same 2180 tensors, the same declared-but-EMPTY MTP head
  # that oMLX detects and skips. The quantization and the base checkpoint are the
  # only differences, so the pair is a controlled test with no confound. It is not
  # a new niche on the roster.
  #
  # 15.34 GB resident (oMLX's `actual:`, the figure the other rows quote). Read as
  # GiB it is 16.47 GB, 0.42 GB over the 16.05 GB of weights on disk — so never
  # subtract 15.34 from a GB budget. Door charge 61.5/63.1 s on a ~12.8k prompt
  # against Bonsai's 56.7/59.6 the same day; decode 20.4/21.0 tok/s short and
  # 18.6 at 20k against 36.4/34.6 and 25.0/24.4. Same 2,048 cache block, warm
  # restore 3.4 s, patience ceiling 21,127 tokens. THE QUANT GAP IS ALMOST PURELY
  # DECODE: 2.03x the store buys 0.58x the decode rate for only ~7% more prefill,
  # which is what bandwidth-bound decode and compute-bound prefill predict.
  #
  # THE RATIO IS WHAT CARRIES, NOT THE ABSOLUTE RATE. Both numbers here were taken
  # in one harness on one day: Bonsai decodes 1.33x this model at 20k and 1.71x at
  # a short prompt. The absolute agentic rate depends on the lane you read it on —
  # oMLX logs end-to-end when not streaming and decode-only when streaming, so at
  # 17.7k the same model reads 2.0 or 18.9 tok/s on that flag alone.
  #
  # It rides the VLM lane, as Bonsai and Muse do, so patch-omlx-vlm-tools.mjs
  # covers it and matters to it — without the tool list its parameters lose their
  # schemas. It needs no output-parser patch of ours: oMLX infers its own native
  # qwen3_coder parser and read 78 tool calls over 26 turns with zero defects.
  # 65,536 declared context, 69,632 rail, matching its twin so the two profiles
  # differ in one variable.
  #
  # IT IS THE ONE MODEL ON THIS ROSTER THAT PINS A BEHAVIOUR: reasoning_effort at
  # medium, written to model_settings.json by patch-omlx-mtp.mjs under both id
  # spellings. Its template injects an instruction paragraph at xhigh and NOTHING
  # at medium, so the pin removes an instruction rather than adding a cap. At its
  # own xhigh default it spent the whole 8,192-token budget and answered nothing on
  # 7 of 12 real coding runs; at medium, over 24 runs, it did so ZERO times and the
  # suite ran 3x faster. Read the pin's reason in patch-omlx-mtp.mjs before
  # touching it — it is the opposite result to GLM's reverted thinking pin.
  #
  # CAPABILITY, and every figure below runs WITH that pin. At short prompts it
  # leads: 12/12 and 11/12 pass@1 over two arms against a same-day Bonsai's 7/12,
  # 0 runaways in 24 runs, 1.81 min per solved task against 4.47. At ~17.6k — the
  # length this roster ranks on, and the only one the default may move on — it does
  # NOT separate: 15/18 against 11/18 on pass@1 and 18/18 against 13/18 on pass@<=2,
  # two arms each, which is +2.0/+2.5 once scaled to the 9-run arm the rule was
  # written for. Bonsai's own two arms moved 3 verdicts at that length, so that lead
  # sits inside the incumbent's measured instability. THE DEFAULT DID NOT MOVE: the
  # margin clause did not fire, capability tied, and the tie-break needs BOTH
  # min/solved and resident footprint — this model wins the first (3.14 against
  # 3.50) and loses the second (15.34 GB against 8.44).
  #
  # Do NOT read its 12/12 against the --muse block's 9/12 either. Different day,
  # different build, no side-by-side arm. Only the same-day Bonsai arm compares.
  _model_qwen() {
    model_id="lmstudio-community/Qwen3.8-27B-MLX-4bit"
    model_label="Qwen3.8 27B 4-bit"
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
  # lingering opencode from a previous `ai`/`ai --glm` run keeps requesting its
  # model — and oMLX loads it alongside ours. Two ~19-23GB LLMs can't coexist
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
    printf "    ${c_cyan}        --bonsai${c_reset}      Use Ternary Bonsai 27B 2-bit ${c_dim}(the default, named)${c_reset}\n"
    printf "    ${c_cyan}        --muse${c_reset}        Use Muse Glimmer 30B 4-bit ${c_dim}(18.6 GB resident — the short-prompt one)${c_reset}\n"
    printf "    ${c_cyan}        --glm${c_reset}         Use GLM 4.7 Flash 6-bit ${c_dim}(22.9 GB resident — the fast one)${c_reset}\n"
    printf "    ${c_cyan}        --qwen${c_reset}        Use Qwen3.8 27B 4-bit ${c_dim}(15.3 GB resident — the default's 4-bit twin)${c_reset}\n"
    printf "    ${c_cyan}-k,     --kill${c_reset}        Kill the oMLX server\n"
    printf "    ${c_cyan}-h,     --help${c_reset}        Show this help\n"
    echo ""
    printf "  ${c_bold}Models${c_reset} ${c_dim}(measured on this box; door charge = cold prefill of a 12.8k prompt)${c_reset}\n"
    printf "    ${c_bold}ai${c_reset}           Ternary Bonsai 27B 2-bit   ${c_dim} 8.4 GB · door 58.6s · 38 tok/s · 5/12${c_reset}\n"
    printf "    ${c_bold}ai --muse${c_reset}    Muse Glimmer 30B 4-bit     ${c_dim}18.6 GB · door 64.5s · 26 tok/s · 9/12${c_reset}\n"
    printf "    ${c_bold}ai --glm${c_reset}     GLM 4.7 Flash 6-bit        ${c_dim}22.9 GB · door 21.8s · 68 tok/s · 6/12${c_reset}\n"
    printf "    ${c_bold}ai --qwen${c_reset}    Qwen3.8 27B 4-bit          ${c_dim}15.3 GB · door 62.3s · 21 tok/s · 11/12${c_reset}\n"
    echo ""
    printf "    ${c_dim}Last column is pass@1 over 12 real coding runs at SHORT prompts (W14),${c_reset}\n"
    printf "    ${c_dim}and the tok/s column is short-prompt decode. At ~17.6k the spread is${c_reset}\n"
    printf "    ${c_dim}7 / 8 / 6 and the models stop separating (W21), so the default is the${c_reset}\n"
    printf "    ${c_dim}cheapest per solved task there and the smallest.${c_reset}\n"
    printf "    ${c_dim}--qwen's 11/12 is measured WITH its reasoning_effort=medium pin, and${c_reset}\n"
    printf "    ${c_dim}beside a same-day Bonsai that scored 7/12 rather than the 5/12 above.${c_reset}\n"
    printf "    ${c_dim}Unpinned it scores 5/12, spending the whole output budget on 7 of 12.${c_reset}\n"
    printf "    ${c_dim}At ~17.6k it does NOT separate from the default (15/18 against 11/18${c_reset}\n"
    printf "    ${c_dim}over two arms each, inside the band), so the default did not move.${c_reset}\n"
    printf "    ${c_dim}Weights come from LM Studio's store; ai.sh never downloads a model.${c_reset}\n"
    echo ""
  }

  # ── Retired model flags ──────────────────────────────────────────────
  # A stale `ai -l` in shell history must FAIL, never remap in silence. The old
  # flags and the new roster share no model, so a quiet substitution would run a
  # whole session on a model the user did not choose.
  _retired_flag() {
    local flag="$1" gone="$2"
    _err "Retired flag ${c_bold}${flag}${c_reset} — ${gone} is no longer served"
    _info "The roster is now:"
    _info "  ${c_bold}ai${c_reset}            Ternary Bonsai 27B 2-bit"
    _info "  ${c_bold}ai --muse${c_reset}     Muse Glimmer 30B 4-bit"
    _info "  ${c_bold}ai --glm${c_reset}      GLM 4.7 Flash 6-bit"
    _info "  ${c_bold}ai --qwen${c_reset}     Qwen3.8 27B 4-bit"
  }

  # ── Ensure the selected model is on disk ─────────────────────────────
  # ONE COPY OF EVERY WEIGHT FILE. LM Studio owns the store — the user downloads
  # models by hand there — and oMLX reaches the same bytes through a directory
  # symlink under --model-dir. This launcher therefore NEVER downloads: a missing
  # model fails loudly by repo id instead of quietly writing a second 8-23 GB copy.
  #
  # The symlink is not what makes a model visible: oMLX also scans the HF cache on
  # its own (huggingface.hf_cache_enabled). The link makes --model-dir
  # authoritative — discovery reads it first, so the linked copy wins the duplicate
  # tie-break — and it gives this function a path to verify. Do NOT repoint
  # OMLX_MODEL_DIR at the store instead: that strands bge-m3, which lives under
  # --model-dir and is served from the same process.
  #
  # Idempotent: a correct link is a silent no-op.
  _ensure_model() {
    local store="${hf_hub_dir}/${model_id}"
    local target="${omlx_model_dir}/${model_id}"

    if [[ ! -d "$store" ]] || ! compgen -G "${store}/*.safetensors" >/dev/null 2>&1; then
      _err "Model missing from the LM Studio store: ${c_bold}${model_id}${c_reset}"
      _info "Expected weights in ${c_dim}${store}${c_reset}"
      _info "Download it in LM Studio, then run ${c_dim}ai${c_reset} again. This launcher never downloads."
      return 1
    fi

    # A half-fetched model must fail exactly like an absent one. The shards that
    # did land would otherwise load as a truncated model — a far worse failure,
    # because oMLX reports it as a model error rather than a missing download.
    if compgen -G "${store}/downloading_*" >/dev/null 2>&1 || compgen -G "${store}/*.part" >/dev/null 2>&1; then
      _err "Model still downloading: ${c_bold}${model_id}${c_reset}"
      _info "LM Studio is still fetching shards into ${c_dim}${store}${c_reset}"
      return 1
    fi

    # A real directory here is a second copy of the weights — the one thing this
    # design exists to prevent. Report it; never overwrite it.
    if [[ -e "$target" && ! -L "$target" ]]; then
      _err "A real directory sits where the symlink belongs: ${c_dim}${target}${c_reset}"
      _info "That is a second copy of the weights. Remove it, then run ${c_dim}ai${c_reset} again."
      return 1
    fi

    [[ "$(readlink "$target" 2>/dev/null)" == "$store" ]] && return 0

    mkdir -p "$(dirname "$target")" || return 1
    ln -sfn "$store" "$target" || return 1
    _ok "Weights linked ${c_dim}${target} → ${store}${c_reset}"
  }

  # ── Drop model symlinks whose weights are gone ───────────────────────
  # Removing a model from LM Studio's store leaves its link behind. oMLX skips a
  # dangling link in silence, so this is tidiness rather than correctness — it
  # keeps --model-dir an honest list of what this box can serve. Only broken links
  # are removed, and a broken link holds no data.
  _prune_stale_model_links() {
    [[ -d "$omlx_model_dir" ]] || return 0
    local link removed=0
    while IFS= read -r link; do
      [[ -n "$link" ]] || continue
      [[ -e "$link" ]] && continue                       # target resolves — keep it
      rm -f "$link" && removed=$(( removed + 1 ))
    done < <(find "$omlx_model_dir" -mindepth 1 -maxdepth 2 -type l 2>/dev/null)
    (( removed > 0 )) && _info "Removed ${removed} dangling model symlink(s) ${c_dim}(weights no longer in the store)${c_reset}"
    return 0
  }

  # ── Prune the paged SSD KV cache to the cap ────────────────────────────
  # A BACKSTOP, not the budget. oMLX enforces the budget itself, and across
  # models: _scan_existing_files files a foreign model's blocks in
  # _incompatible_index, _tracked_ssd_size() counts them, and
  # _evict_tracked_until_size walks the LRU across BOTH indexes, so the oldest
  # foreign block is the first to go (upstream 28fe5cb8 / #1915, 2026-06-19, in
  # this build). Do NOT read "skipped_incompatible=N blocks" in the log as a
  # stuck cache: W3 saw 136 blocks / 24.95 GB sit under the 25 GB cap, which is
  # eviction having no reason to fire, and the next block written cleared it —
  # up to _MAX_INLINE_UNLINKS_PER_SAVE (32) unlinks per save, ~9 GB.
  #
  # One orphan survives that, and it is why this function stays. Blocks whose
  # omlx_cache_format_version falls outside _READABLE_CACHE_FORMAT_VERSIONS are
  # skipped by _read_file_metadata, so they enter NO index, count toward NO
  # budget, and are never evicted. The oMLX install is editable, so any pull can
  # bump that version and strand the whole cache. Deleting oldest-first (mtime =
  # LRU, matching oMLX's own intent) is deliberately blunt: reading the version
  # set into this script would copy a constant that drifts, and a drifted copy
  # deletes LIVE blocks — a worse failure than keeping dead ones.
  #
  # Only ever called from _start_server with the server down, so no live process
  # holds these blocks; a block is content-addressed, so a later cache lookup for
  # a deleted one is just a miss → recompute (the safe failure mode).
  #
  # It does NOT prune on a model switch, by W13's decision. A switch does not
  # kill the outgoing model's blocks, it makes them dormant: they serve a warm
  # restore at ~3.4 s against ~150 s cold when you switch back. With four
  # profiles a switch is ordinary, and oMLX already evicts them first when the
  # budget binds.
  _prune_cache() {
    local dir=$1 max_gb=$2
    [[ -d "$dir" && -n "$max_gb" && "$max_gb" -gt 0 ]] 2>/dev/null || return 0
    find "$dir" -name '.DS_Store' -type f -delete 2>/dev/null   # Finder cruft
    local max_bytes=$(( max_gb * 1024 * 1024 * 1024 )) cur_bytes
    cur_bytes=$(( $(du -sk "$dir" 2>/dev/null | awk '{print $1+0}') * 1024 ))
    (( cur_bytes > max_bytes )) || return 0
    _info "Pruning KV cache: $(awk -v b="$cur_bytes" 'BEGIN{printf "%.1f", b/1073741824}')GB on disk over ${max_gb}GB cap (blocks oMLX cannot index, likely a cache-format bump)"
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
    # nohup + disown, not a bare `&`. Without them the server stays a child of
    # the launching shell and inside its job table, so it dies with that shell —
    # closing the terminal you typed `ai` in takes the server down with it, and
    # a model load is 3-9 s plus a cold door charge to get back. Seen twice on
    # 2026-08-13: a graceful shutdown mid-session with nothing in the log but
    # "Engine pool shutdown", which reads exactly like a crash and is not one.
    # macOS has no setsid, so this is as detached as it gets: nohup ignores
    # SIGHUP, disown drops it from the shell's jobs. A signal aimed at the whole
    # process group would still reach it — _kill_server is the supported way to
    # stop it.
    nohup "$omlx_bin" serve \
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
    # $! is still the server: nohup execs in place rather than forking, so the
    # pid file and _wait_for_server's `kill -0` check both stay correct.
    disown "$server_pid" 2>/dev/null || true
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
        # Line 1: served model id. Line 2: the build serving it (binary path plus
        # the source checkout's commit). Recorded so a same-model/different-build
        # case still forces a restart — an in-place oMLX upgrade keeps the binary
        # path identical, so the commit is the half that actually moves.
        printf "%s\n%s\n" "$model_id" "$omlx_build" > "$state_file"
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

  # ── Warm the prompt prefix ─────────────────────────────────────────────
  # opencode puts the system prompt, AGENTS.md, the skill list and every tool
  # definition BEFORE your message. Measured in this repo: 13,364 tokens for a
  # message as short as "hi". Muse prefills that in 88.2 s cold and 7.4 s warm,
  # so the wait is a door charge on a prefix that changes only when the date,
  # the directory or the config changes — not once per message. Every number in
  # this block was measured on Muse Glimmer, which was the default when the
  # warm-up was written; it is --muse now, and nothing here was re-measured on
  # Bonsai. The mechanism is the same on every profile; the seconds are not.
  #
  # This sends that prefix through `opencode run` with max_tokens pinned to 1,
  # in the caller's directory, on the same model. opencode therefore builds the
  # prompt exactly as the real session will, and oMLX holds the blocks before
  # you finish typing. It decodes nothing.
  #
  # Nothing here is fatal. A warm-up that fails costs only the door charge you
  # already pay today, so every step is best-effort and silent.
  #
  # IT IS WORTHLESS UNLESS THE SYSTEM PROMPT IS BYTE-STABLE, which is measured,
  # not feared. opencode scans three skill directories, dedupes by NAME and
  # races them for the tie-break, so the <location> line of a duplicated skill
  # changes between launches. Three identical `opencode run` invocations in one
  # directory produced THREE different system prompts, diverging at token
  # ~4,400; a warm-up under those conditions reused 4,096 of 13,469 tokens and
  # saved 1.1 s of 101.3 s. With one scan directory the same three runs hash
  # identically. That is why ~/.agents/skills is now the single source and why
  # the launch below sets OPENCODE_DISABLE_CLAUDE_CODE_SKILLS — if a future
  # opencode adds a fourth scan path, this warm-up silently stops paying, and
  # the symptom is a cold first turn rather than an error.
  #
  # OFF BY DEFAULT, because a real launch measured it losing. On a cold server
  # the warm-up and the first real turn CONTEND: oMLX has no request priority
  # (`omlx serve` exposes only --max-concurrent-requests), so a warm-up cannot
  # yield, and prefill on one GPU serialises. One launch logged the warm-up
  # holding the device for 50.62 s while the user's turn — submitted 10 s after
  # the server came up — waited behind it, turning a ~90 s first answer into
  # 2 m 14 s. The warm-up only pays if you launch `ai` and then do not type for
  # a minute. Set AI_WARM_PREFIX=1 if that is your habit.
  #
  # MCP now stays ON in the warm-up, and the reason is worth keeping. Muse's
  # template renders a compact "// Tool metadata" NAME LIST before the full
  # schemas, so dropping the MCP tools diverges the prefix a few hundred tokens
  # into the tool section rather than late — measured at reused=6,144 of 13,324.
  # An MCP-less warm-up therefore prefilled 11,907 tokens to save 6,144, and the
  # box did 43 % more total work than with no warm-up at all. AI_WARM_PREFIX_MCP=0
  # restores that behaviour and is kept only to reproduce the measurement.
  _warm_prefix() {
    (( warm_prefix )) || return 0
    command -v node >/dev/null 2>&1 || return 0

    # max_tokens goes under the MODEL's options, not the provider's: opencode
    # spreads a model's options object verbatim into the request body, while the
    # provider's options configure the SDK client (baseURL, apiKey, timeouts).
    # The title agent is disabled here too, so a warm-up never spends a second
    # request — and a second batch slot — naming a session you will never open.
    local warm_cfg=""
    warm_cfg=$(node -e '
const base = process.argv[1] ? JSON.parse(process.argv[1]) : {};
base.$schema = "https://opencode.ai/config.json";
base.provider = base.provider || {};
base.provider.mlx = base.provider.mlx || {};
base.provider.mlx.models = base.provider.mlx.models || {};
const models = base.provider.mlx.models;
models[process.argv[2]] = models[process.argv[2]] || {};
models[process.argv[2]].options = Object.assign({}, models[process.argv[2]].options, { max_tokens: 1 });
base.agent = base.agent || {};
base.agent.title = Object.assign({}, base.agent.title, { disable: true });
if (process.argv[3] !== "1") {
  const cfg = JSON.parse(require("fs").readFileSync(process.argv[4], "utf8"));
  const m = Object.assign({}, base.mcp);
  for (const k of Object.keys(cfg.mcp || {})) m[k] = Object.assign({}, m[k], { enabled: false });
  base.mcp = m;
}
process.stdout.write(JSON.stringify(base));
' "$oc_config_content" "$model_id" "$warm_mcp" "${ai_dir}/opencode.json" 2>/dev/null)
    [[ -n "$warm_cfg" ]] || return 0

    # OPENCODE_MEM_EXCLUDE_DIRS=/ makes the patched opencode-mem skip this run
    # for capture AND recall. Capture is the point: the summarizer is a raw
    # client that never sees max_tokens above, so an uncapped 99 s summary of a
    # one-word warm-up would outlive the warm-up itself. Skipping recall costs
    # nothing, because the plugin unshifts recalled memories onto the USER
    # message, which sits after the whole shared prefix.
    # Every variable that shapes the prompt must match the real launch below, or
    # the warm-up caches a prefix the session never asks for.
    ( OPENCODE_CONFIG_CONTENT="$warm_cfg" \
      OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 \
      OPENCODE_MEM_EXCLUDE_DIRS="/" \
      OPENCODE_MEM_MODEL="$model_id" \
      opencode run --dir "$caller_dir" -m "${oc_provider}/${oc_model}" \
        --title "ai.sh prefix warm-up" "warm" \
        >"$warm_log" 2>&1 ) &
    disown 2>/dev/null
    _info "Warming the prompt prefix in the background ${c_dim}(~13k tokens; AI_WARM_PREFIX=0 to skip)${c_reset}"
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
      _err "Missing dependency: ${c_bold}omlx${c_reset} (expected at ${c_dim}${omlx_bin}${c_reset})"
      _info "Build: ${c_dim}git clone https://github.com/jundot/omlx ${omlx_src_dir} \\"
      _info "  && uv venv ${omlx_venv} --python 3.12 \\"
      _info "  && VIRTUAL_ENV=${omlx_venv} uv pip install -e ${omlx_src_dir}${c_reset}"
      missing=1
    fi
    return $missing
  }

  # ── Main logic ───────────────────────────────────────────────────────
  local action=""               # "" | "kill" | "help"
  # "" means no model flag was given, so bare `ai` takes the default. The default
  # is named "bonsai" below rather than tracked as the string "default": the GLM
  # fail-safe further down keys on the profile NAME, and a sentinel that moves
  # with the default would silently point it at the wrong model.
  local profile=""              # "" (default) | "glm" | "bonsai" | "muse" | "qwen"
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
      --glm|-glm)
        # Model flags are mutually exclusive — picking the wrong one silently
        # costs a server restart and a fresh model load, so fail loudly.
        if [[ -n "$profile" && "$profile" != "glm" ]]; then
          _err "Conflicting model flags: --${profile} and $1"
          _show_help
          return 1
        fi
        profile="glm"
        shift
        ;;
      --bonsai|-bonsai)
        # Names the default explicitly. Bare `ai` lands on the same model, so
        # this flag documents an intent rather than changing one.
        if [[ -n "$profile" && "$profile" != "bonsai" ]]; then
          _err "Conflicting model flags: --${profile} and $1"
          _show_help
          return 1
        fi
        profile="bonsai"
        shift
        ;;
      --muse|-muse)
        # Muse Glimmer was the default until 2026-08-14. The flag already existed
        # then and named the same model, so an existing habit or script keeps
        # working across the move, and keeps reading correctly.
        if [[ -n "$profile" && "$profile" != "muse" ]]; then
          _err "Conflicting model flags: --${profile} and $1"
          _show_help
          return 1
        fi
        profile="muse"
        shift
        ;;
      --qwen|-qwen)
        # A SLOT, not a model: the newest Qwen answers to this flag, and a later
        # one replaces the model under it rather than earning a flag of its own.
        # See _model_qwen for which Qwen fills it today.
        if [[ -n "$profile" && "$profile" != "qwen" ]]; then
          _err "Conflicting model flags: --${profile} and $1"
          _show_help
          return 1
        fi
        profile="qwen"
        shift
        ;;
      -l|--lite)
        _retired_flag "$1" "Qwen 3.6 35B-A3B oQ6 +MTP"
        return 1
        ;;
      -g|--gemma|-gemma)
        _retired_flag "$1" "Gemma 4 12B QAT+OptiQ 4-bit"
        return 1
        ;;
      --macaw|-macaw)
        _retired_flag "$1" "Macaw 4-bit (LFM2.5-2.6B)"
        return 1
        ;;
      -hybrid|--hybrid|--no-hybrid|-no-hybrid)
        # The @advisor cloud subagent is gone, so both halves of the switch are
        # retired together. Neither is silently accepted: --no-hybrid would now
        # be a no-op that reads like a guarantee, and -hybrid would promise a
        # cloud path this launcher can no longer open.
        _err "Retired flag ${c_bold}$1${c_reset} — the ${c_bold}@advisor${c_reset} cloud subagent is removed"
        _info "No launch has a path off this box. ${c_dim}Nothing to enable or disable.${c_reset}"
        return 1
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
    glm)  _model_glm ;;
    muse) _model_muse ;;
    qwen) _model_qwen ;;
    *)    _model_bonsai ;;   # "" (bare `ai`) and "bonsai" both land here
  esac
  _resolve_runtime
  local oc_model="$model_id"

  case "$action" in
    help) _show_help; return 0 ;;
    kill) _kill_server; return 0 ;;
  esac

  _check_deps || return 1

  _reap_orphan_mcps

  # Verify the selected model's weights and link them under --model-dir, so the
  # server never lazy-fails on the first request. This never downloads: LM Studio
  # owns the store and the user fetches models there by hand.
  _prune_stale_model_links
  _ensure_model || return 1

  # Apply per-model oMLX settings that aren't server CLI flags. They live in
  # ~/.omlx/model_settings.json, which oMLX reads at model load — so a running
  # server must be restarted to pick up a change (the model-switch restart below
  # handles the common case). The roster pins ONE BEHAVIOUR, on ONE model:
  # Qwen3.8's reasoning_effort at medium — see _model_qwen above for the 24-run
  # measurement behind it. The other three pass their serve check at their own
  # defaults and pin nothing, and MTP stays off unless ai.env opts in. What this
  # also writes is one max_context_window RAIL per model, against clients that
  # never read opencode.json at all. The mechanism is where any further pin
  # lands, and it re-asserts our values over an oMLX admin-panel toggle.
  # Idempotent merge: it only writes when a value differs, and never clobbers
  # other models/keys.
  #
  # THE TWO MTP VARIABLES MUST BE MARKED FOR EXPORT HERE. ai.env is SOURCEd, not
  # read under `set -a`, so a plain `AI_QWEN_MTP=1` in it is a shell variable and
  # nothing more. Every other variable in that file is read by ai.sh ITSELF, where
  # a shell variable is enough; these two are read by the node process below, which
  # inherits only the ENVIRONMENT. Without these lines the documented opt-in is a
  # silent no-op — the toggle reads as set, the settings file still says false, and
  # the only symptom is a decode rate that never moves. `export` on an unset name
  # marks the attribute without creating an empty variable, so this is safe when
  # ai.env says nothing, and it lets ai.env use either spelling.
  export AI_QWEN_MTP AI_QWEN_MTP_DEPTH
  local omlx_base_dir="${OMLX_BASE_DIR:-${HOME}/.omlx}"
  if command -v node >/dev/null 2>&1 && [[ -f "${ai_dir}/scripts/patch-omlx-mtp.mjs" ]]; then
    node "${ai_dir}/scripts/patch-omlx-mtp.mjs" "${omlx_base_dir}/model_settings.json" >/dev/null 2>&1
  fi

  # Correct oMLX's MLA KV estimate before the server starts. Unpatched, oMLX sizes
  # GLM 4.7 Flash's KV with the uniform MHA formula and charges ~362 KB/token against
  # a real 52.9 — a 7.08x over-count that puts 65,536 context out of reach and
  # throttles the prefill chunk from ~25k tokens up. The patch is one loop in one
  # function, and it cannot reach the other two models: the estimator returns early
  # unless the config carries BOTH kv_lora_rank and qk_rope_head_dim, which only GLM
  # does. See .scratch/model-roster-swap tickets W5 and W12.
  #
  # oMLX is an editable install, so the source IS what runs — but only from the next
  # server start, because a live process already imported the old module. Appending
  # to omlx_build makes the state-file build check below restart a stale server on
  # its own, instead of leaving it answering with the old arithmetic.
  local mla_patch_ok=0
  if command -v node >/dev/null 2>&1 && [[ -f "${ai_dir}/scripts/patch-omlx-mla-kv.mjs" ]]; then
    if node "${ai_dir}/scripts/patch-omlx-mla-kv.mjs" "$omlx_src_dir" >/dev/null 2>&1; then
      mla_patch_ok=1
      omlx_build="${omlx_build}+mlakv"
    fi
  fi

  # Harden Muse Glimmer's output parser, same mechanism, different model.
  # Muse frames messages as `<|start|>assistant to=<name><|message|>BODY`, and
  # oMLX SUPPRESSES a body whose recipient is neither self nor user, parsing the
  # tool call only at finalize. Every defect below follows from that: when the
  # parse fails the tokens are already gone, and the client gets an empty answer
  # with finish_reason=stop, which opencode reads as "no tool call" and leaves
  # the agent loop over. Four fixes — a corrupt invoke name (`bash<|message|>`),
  # a stray <|message|> that leaks the tool XML to the user, a header scan that
  # disagreed with the splitter and silently dropped whole turns, and a rail
  # that surfaces the raw text rather than answer nothing at all. One model
  # only: this adapter is selected for muse_glimmer alone.
  # The build suffix carries a version, so a server running the older patch
  # restarts instead of looking current.
  local muse_tc_patch_ok=0
  if command -v node >/dev/null 2>&1 && [[ -f "${ai_dir}/scripts/patch-omlx-muse-toolcall.mjs" ]]; then
    if node "${ai_dir}/scripts/patch-omlx-muse-toolcall.mjs" "$omlx_src_dir" >/dev/null 2>&1; then
      muse_tc_patch_ok=1
      omlx_build="${omlx_build}+musetc5"
    fi
  fi

  # Deliver the request's tool list to the VLM lane's output parser. oMLX reads
  # request.tools when it builds that parser, Request carries the field, and
  # engine_core.add_request forwards it — but VLMBatchedEngine.chat/stream_chat
  # hold `tools` as an explicit parameter and never pass it on, so it is always
  # None here. That makes the dotted-name repair above DEAD CODE: it rewrites
  # `webfetch.webfetch` to `webfetch` only when it can prove the prefix is a
  # real tool, and with no tool list it can prove nothing. It also strips the
  # schemas from parameter coercion. Muse Glimmer, Bonsai and Qwen3.8 all ride
  # this lane; GLM does not. Qwen3.8 needs no parser patch of ours but still needs
  # this one — W5 proved it live, by a string-typed parameter that stays "5"
  # instead of arriving as the number 5.
  local vlm_tools_patch_ok=0
  if command -v node >/dev/null 2>&1 && [[ -f "${ai_dir}/scripts/patch-omlx-vlm-tools.mjs" ]]; then
    if node "${ai_dir}/scripts/patch-omlx-vlm-tools.mjs" "$omlx_src_dir" >/dev/null 2>&1; then
      vlm_tools_patch_ok=1
      omlx_build="${omlx_build}+vlmtools2"
    fi
  fi

  # Record which native Metal kernels this install can actually IMPORT. oMLX
  # ships four — bonsai (2-bit decode qmv + a fused spec-decode verify),
  # glm_moe_dsa, minimax_m3 and qwen35_prefill — and a plain `pip install -e`
  # builds NONE of them. oMLX's own docstring says the affected model families
  # then "silently fall back to much slower generic paths", and three of this
  # roster's four models sit in those families. Build them with the Metal
  # toolchain present (Xcode CLI tools) and NOT through a plain reinstall:
  #
  #   OMLX_WITH_CUSTOM_KERNEL=1 uv pip install -e "$OMLX_SRC_DIR" \
  #     --no-deps --python "$OMLX_VENV/bin/python" --reinstall-package omlx
  #
  # --no-deps is load-bearing: the pyproject pins runtime deps by FLOOR, so a
  # plain reinstall can drag mlx-vlm/transformers forward and take the parser
  # patches above with it. The build itself takes ~27 s.
  #
  # Measured on this box 2026-08-17, cold prefill isolated with max_tokens=1 and
  # a unique nonce per run (so cached_tokens=0), comparing arms at the SAME cache
  # occupancy: 12.8k door charge 86.6 s -> 76.4 s (1.13x), 17.6k 136.3 s ->
  # 111.3 s (1.22x). Decode does not move — 18.3 -> 19.1 tok/s, inside noise —
  # which is expected, since three of the four are prefill kernels and bonsai's
  # decode kernel does not apply to a 4-bit model. The GDN route stays at its
  # default: OMLX_GDN_IMPL=chunked measured 2.7% SLOWER and is not set anywhere.
  # Read those figures beside the drift the same run found: the SSD cache filling
  # from 12 GB to its 25 GB cap cost 35% on the identical prefill with the
  # kernels held constant — a LARGER lever than this one, and still unpriced.
  #
  # Why this belongs in the build id: a rebuild does not move the source
  # checkout's git HEAD, so `<binary>@<rev>` is byte-identical either side of
  # one. Without this suffix a server started on the unbuilt code looks current
  # to the state-file check below and keeps serving the slow paths forever.
  # The check asks the installed package what it can import rather than globbing
  # for .so files, so a present-but-ABI-broken extension reads as absent — which
  # is what it is. nanobind is pinned to mlx's exact version precisely because a
  # mismatch makes every kernel reject mlx arrays at the type caster. It costs
  # ~0.06 s: omlx.custom_kernels is a leaf package and imports no server code.
  #
  # Nothing is appended when no kernel is importable, so a box that never builds
  # them produces the build line it always did and is not restarted for this.
  if [[ -x "${omlx_venv}/bin/python" ]]; then
    local kernel_py='from omlx.custom_kernels import native_kernel_status as s
n = sorted(k for k, v in s().items() if v.get("available"))
print("+kernels%d%s" % (len(n), "".join(x[0] for x in n)) if n else "")'
    local kernel_tag
    kernel_tag=$("${omlx_venv}/bin/python" -c "$kernel_py" 2>/dev/null)
    omlx_build="${omlx_build}${kernel_tag}"
  fi

  # ── Server management ──────────────────────────────────────────────
  local running_pid
  running_pid=$(_server_pid)

  if [[ -n "$running_pid" ]]; then
    if _server_healthy; then
      local running_model="" running_build=""
      if [[ -f "$state_file" ]]; then
        { IFS= read -r running_model; IFS= read -r running_build; } < "$state_file" 2>/dev/null
      fi
      if [[ "$running_model" != "$model_id" ]]; then
        _warn "Server running with different model (${running_model:-unknown})"
        _info "Switching to ${c_bold}${model_label}${c_reset}"
        _kill_server
        _start_server || return 1
      elif [[ "$running_build" != "$omlx_build" ]]; then
        # Same model, a different oMLX build — or a state file written before the
        # build was recorded this way, where we cannot tell. Restart either way:
        # an in-place upgrade leaves a running server on the old code, which is
        # invisible from the outside and diverges from the model settings and
        # architecture support the new build brought in.
        _warn "Server running from a different oMLX build (${running_build:-unrecorded})"
        _info "Restarting on ${c_dim}${omlx_build}${c_reset}"
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
  # The MCP kill-switch. opencode deep-merges OPENCODE_CONFIG_CONTENT over the
  # global opencode.json (later wins), so emitting {enabled:false} for every MCP
  # server declared there disables them all for this session only — no edit to
  # opencode.json, and new servers added later are covered automatically. Passed
  # to the opencode launch below; an empty value is ignored by opencode.
  #
  # NO PROFILE CLAIMS THIS TODAY. The retired `-l` owned it; the machinery stays
  # because it costs nothing while idle and is one assignment away from being
  # live, should a profile on the new roster want to run MCP-free.
  local mcp_free=0
  local oc_config_content=""
  if (( mcp_free )); then
    if command -v node >/dev/null 2>&1 && [[ -f "${ai_dir}/opencode.json" ]]; then
      oc_config_content=$(node -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const m={};for(const k of Object.keys(c.mcp||{}))m[k]={enabled:false};process.stdout.write(JSON.stringify({$schema:"https://opencode.ai/config.json",mcp:m}));' "${ai_dir}/opencode.json" 2>/dev/null)
    fi
    _info "MCPs disabled for this session ${c_dim}(no smart-coding RAG / chrome-devtools)${c_reset}"
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

  # Fail-safe for the MLA KV patch above. If its anchor is gone — an oMLX upgrade
  # moved the code — oMLX charges GLM 362 KB/token again and rejects every prompt
  # past ~20k mid-session, while opencode.json still advertises 65,536. Rather than
  # meet that one failed turn at a time, advertise the measured-safe mid-session cap
  # for THIS SESSION ONLY, through the same OPENCODE_CONFIG_CONTENT overlay the MCP
  # kill-switch uses (opencode deep-merges it last, so it wins). 24,576 is chosen
  # from W5's measurements: 20,450 tokens answered even at 36 GB in use, and ~37,500
  # was rejected mid-session, so the safe point sits between them.
  #
  # Only the GLM profile needs this. Bonsai and Muse never reach the patched code
  # and hold a flat 65,536 (W13). The max_context_window rail in model_settings.json
  # reads 36,864 for GLM (W12) — one 4,096-token block above its declared 32,768. It
  # is a belt for clients that never read opencode.json at all, not the binding cap,
  # and it does NOT fall back with this overlay: a degraded session advertises 24,576
  # to opencode while the rail stays at 36,864, which is the safe way round.
  # Warn when Muse loses its tool-call hardening. There is no rail to raise here:
  # the failure mode is a wasted turn, not a wrong answer, so the session is told
  # rather than capped. Keyed on the MODEL, not the profile. Muse Glimmer serves
  # only --muse today, but it served bare `ai` as well until 2026-08-14, and a
  # test on the flag would have missed half its sessions then — the trap W18
  # caught on the GLM fail-safe. Keying on the model id survives the next move of
  # the default; keying on the profile name has to be revisited at every move.
  if (( ! muse_tc_patch_ok )) && [[ "$model_id" == *Muse-Glimmer* ]]; then
    _warn "oMLX Muse output-parser patch did not apply — the upgrade moved the code"
    _info "Tool calls may be rejected as unknown tools, or a turn may end with no answer at all ${c_dim}(re-anchor scripts/patch-omlx-muse-toolcall.mjs)${c_reset}"
  fi

  # Keyed on the VLM lane, not on one model: Bonsai and Qwen3.8 lose the same
  # delivery. GLM rides the batched lane and is unaffected, so it is not warned.
  # Every test here is on the MODEL id, so the next move of the default costs no
  # edit — and a new model on this lane must be added here by hand.
  if (( ! vlm_tools_patch_ok )) && [[ "$model_id" == *Muse-Glimmer* || "$model_id" == *Ternary-Bonsai* || "$model_id" == *Qwen3.8-27B* ]]; then
    _warn "oMLX VLM tool-list patch did not apply — the upgrade moved the code"
    _info "The output parser cannot see the tool list, so tool parameters lose their schemas and Muse's dotted-name repair goes inert ${c_dim}(re-anchor scripts/patch-omlx-vlm-tools.mjs)${c_reset}"
  fi

  local glm_degraded_context=24576
  if (( ! mla_patch_ok )) && [[ "$profile" == "glm" ]]; then
    if command -v node >/dev/null 2>&1; then
      local degraded=""
      degraded=$(node -e '
const base = process.argv[1] ? JSON.parse(process.argv[1]) : {};
base.$schema = "https://opencode.ai/config.json";
base.provider = base.provider || {};
base.provider.mlx = base.provider.mlx || {};
base.provider.mlx.models = base.provider.mlx.models || {};
const models = base.provider.mlx.models;
models[process.argv[2]] = models[process.argv[2]] || {};
const m = models[process.argv[2]];
m.limit = m.limit || {};
m.limit.context = Number(process.argv[3]);
process.stdout.write(JSON.stringify(base));
' "$oc_config_content" "$model_id" "$glm_degraded_context" 2>/dev/null)
      [[ -n "$degraded" ]] && oc_config_content="$degraded"
    fi
    _warn "oMLX MLA KV patch did not apply — the upgrade moved the code"
    _info "Context capped at ${c_bold}${glm_degraded_context}${c_reset} for this session ${c_dim}(re-anchor scripts/patch-omlx-mla-kv.mjs)${c_reset}"
  fi

  # Fire the warm-up here, not at the launch below: everything that follows —
  # the memory check, the plugin symlinks, the stale-file cleanup — runs while
  # oMLX prefills, and that is lead time the first message does not have to pay
  # for.
  # It reads the final $oc_config_content, so a degraded GLM session warms the
  # same prefix it will then use.
  _warm_prefix

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
      # opencode-mem.jsonc's own pick in alongside an opt-in profile and thrashing the
      # memory guard.
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
  # get skipped, especially by a local model). opencode auto-loads any file
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

  # Clean up scraps from removed experiments — the AFK agents, its loop plugin
  # and the /lock command, plus the withdrawn @advisor cloud subagent and its
  # egress logger. A stale symlink or leftover file must never re-introduce an
  # auto-driving agent, or a path off this box, into a normal session. Safe on
  # every launch, and the only thing standing between an old install and a
  # resurrected cloud path: opencode auto-loads whatever sits in these
  # directories at startup, so removing the repo copy alone is not enough.
  rm -f "${HOME}/.config/opencode/agents/afk.md" \
        "${HOME}/.config/opencode/agents/afk-impl.md" \
        "${HOME}/.config/opencode/agents/afk-planner.md" \
        "${HOME}/.config/opencode/agents/afk-cagetest.md" \
        "${HOME}/.config/opencode/agents/grill.md" \
        "${HOME}/.config/opencode/agents/advisor.md" \
        "${HOME}/.config/opencode/plugins/afk-loop.js" \
        "${HOME}/.config/opencode/plugins/advisor-egress-log.js" \
        "${HOME}/.config/opencode/command/lock.md" \
        "${HOME}/.config/opencode/command/afk.md" \
        "${HOME}/.config/opencode/command/afk-issue.md" 2>/dev/null

  # ── Launch frontend ──────────────────────────────────────────────────
  echo ""
  cd "$caller_dir" || return 1

  _info "Launching ${c_bold}opencode${c_reset} with ${c_bold}${oc_provider}/${oc_model}${c_reset}"
  echo ""
  # OPENCODE_MEM_EXCLUDE_DIRS: never capture/recall memory from these trees. Prepend
  # sensitive client-repo roots via ai.env; read by the patched opencode-mem
  # (patch-opencode-mem-exclude.mjs).
  # OPENCODE_MEM_MODEL points the opencode-mem summarizer at the SAME model this
  # session runs (read by the patched config.js), so auto-capture never loads a second
  # 8-23GB model beside it and thrashes the memory guard into a 507 loop.
  # OPENCODE_CONFIG_CONTENT is an inline config opencode deep-merges last; it carries
  # {enabled:false} for every MCP server when the kill-switch above is set, and is
  # empty otherwise (empty = ignored by opencode, so a session keeps its MCPs).
  #
  # OPENCODE_DISABLE_CLAUDE_CODE_SKILLS keeps the system prompt BYTE-STABLE between
  # launches, which is what lets oMLX's paged cache match a prefix at all. opencode
  # scans ~/.claude/skills, ~/.agents/skills and ~/.config/opencode/skills, dedupes
  # by name, and races the directories for the tie-break — three identical runs in
  # one directory produced three different prompts, diverging at token ~4,400 on
  # nothing but a <location> line. ~/.agents/skills is now the single source (the
  # other two held only symlinks into it), so this variable retires the last
  # duplicate scan. It is opencode-only: Claude Code reads ~/.claude/skills itself
  # and is untouched. No skill is lost — measured at 29 before and after.
  #
  # The explicit `-m mlx/<id>` is what makes `ai` local regardless of opencode.json's
  # default model (now a Vercel AI Gateway model, for bare `opencode` sessions): the
  # CLI flag wins over the config, so every profile pins its own local model.
  OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 \
  OPENCODE_MEM_EXCLUDE_DIRS="${OPENCODE_MEM_EXCLUDE_DIRS:-}" \
  OPENCODE_MEM_MODEL="$model_id" \
  OPENCODE_CONFIG_CONTENT="$oc_config_content" \
  opencode -m "${oc_provider}/${oc_model}" "${passthrough_args[@]}"
  return $?
}

# Allow both sourcing and direct execution
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && ai "$@"
